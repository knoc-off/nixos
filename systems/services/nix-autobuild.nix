# Weekly (or on-demand) refresh of the flake's lockfile, verified by building
# everything cacheJobs names, and published to the `built` branch. See the
# repo-root discussion in nix-cache.nix for why this exists: this is the half
# that keeps optiplex's cache actually current.
#
# Deliberately not DynamicUser: the same nix-autobuild-run script is reused
# both by the timer-driven service below and by ad hoc `systemd-run` for
# targeted updates (nix-autobuild-now), and a fixed system user keeps state
# ownership (the git clone, gcroots) consistent between the two call sites
# without re-deriving a DynamicUser's ephemeral uid each time.
{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.services.nixAutobuild;

  nix = getExe' config.nix.package "nix";

  # GitHub's published ssh-ed25519 host key (see
  # https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/githubs-ssh-key-fingerprints).
  # Getting this wrong only fails closed (git over ssh refuses to connect), so
  # pinning it here -- rather than trusting whatever a first connection sees --
  # is strictly safer than TOFU. Worth reconfirming against GitHub's docs at
  # bootstrap time regardless.
  githubKnownHost = "github.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl";

  runner = pkgs.writeShellApplication {
    name = "nix-autobuild-run";
    runtimeInputs = [
      pkgs.git
      pkgs.nix-fast-build
      pkgs.nix-eval-jobs
      pkgs.curl
      pkgs.coreutils
    ];
    text = ''
      state_dir=${escapeShellArg cfg.stateDir}
      repo_dir="$state_dir/nixos"
      gcroots_dir="$state_dir/gcroots"
      results_dir="$state_dir/results"
      known_hosts="$state_dir/known_hosts"
      date_stamp=$(date +%Y%m%d-%H%M%S)

      mkdir -p "$gcroots_dir" "$results_dir"
      printf '%s\n' ${escapeShellArg githubKnownHost} > "$known_hosts"

      export GIT_SSH_COMMAND="ssh -i $CREDENTIALS_DIRECTORY/deploy-key -o IdentitiesOnly=yes -o UserKnownHostsFile=$known_hosts"

      notify() {
        local priority="$1" title="$2" message="$3"
        curl -fsS \
          -H "Title: $title" \
          -H "Priority: $priority" \
          -H "Authorization: Bearer $(cat "$CREDENTIALS_DIRECTORY/ntfy-token")" \
          -d "$message" ${escapeShellArg "${cfg.ntfyUrl}/${cfg.ntfyTopic}"} || true
      }

      if [ ! -d "$repo_dir/.git" ]; then
        git clone ${escapeShellArg cfg.repoUrl} "$repo_dir"
      fi
      cd "$repo_dir"
      git fetch origin main
      git checkout -B autobuild-work origin/main
      git clean -fdx

      # No args: update every input. With args: update just those, e.g.
      # `nix-autobuild-now hyprland noctalia`. Same subcommand either way --
      # `nix flake update inputs...` is the current interface (the older
      # `nix flake lock --update-input` form still works but is legacy).
      ${escapeShellArg nix} flake update "$@"
      if [ "$#" -eq 0 ]; then
        update_summary="all inputs"
      else
        update_summary="$*"
      fi

      x86_ok=1
      nix-fast-build \
        --nix ${escapeShellArg nix} \
        --flake ".#cacheJobs.x86_64-linux" \
        --systems x86_64-linux \
        --skip-cached \
        --no-nom \
        --retries 1 \
        --eval-workers ${toString cfg.evalWorkers} \
        --eval-max-memory-size ${toString cfg.evalMaxMemoryMiB} \
        --out-link "$gcroots_dir/$date_stamp-x86_64" \
        --result-file "$results_dir/x86_64-$date_stamp.json" \
        || x86_ok=0

      aarch64_ok=0
      if [ "$x86_ok" -eq 1 ]; then
        aarch64_ok=1
        nix-fast-build \
          --nix ${escapeShellArg nix} \
          --flake ".#cacheJobs.aarch64-linux" \
          --systems aarch64-linux \
          --skip-cached \
          --no-nom \
          --retries 1 \
          --eval-workers ${toString cfg.evalWorkers} \
          --eval-max-memory-size ${toString cfg.evalMaxMemoryMiB} \
          --out-link "$gcroots_dir/$date_stamp-aarch64" \
          --result-file "$results_dir/aarch64-$date_stamp.json" \
          || aarch64_ok=0
      fi

      # Retention: keep the last N dated generations (both arches count as one
      # "generation" by date_stamp prefix). Older ones lose their gcroot, so
      # nix.gc reclaims the store paths they alone were pinning; their result
      # JSONs go too, since they only describe builds we can no longer inspect.
      # shellcheck disable=SC2012
      ls -1 "$gcroots_dir" \
        | sed -E 's/-(x86_64|aarch64)$//' \
        | sort -ru \
        | tail -n "+$((${toString cfg.keepGenerations} + 1))" \
        | while read -r old_stamp; do
            rm -rf "''${gcroots_dir:?}/$old_stamp-x86_64" "''${gcroots_dir:?}/$old_stamp-aarch64"
            rm -f "''${results_dir:?}/x86_64-$old_stamp.json" "''${results_dir:?}/aarch64-$old_stamp.json"
          done

      if [ "$x86_ok" -eq 1 ]; then
        git add flake.lock
        git commit -m "autobuild: $date_stamp ($update_summary)" --allow-empty
        git push --force origin "HEAD:${cfg.branch}"
        notify default "nix-autobuild: published" \
          "updated: $update_summary. x86_64: ok. aarch64: $([ "$aarch64_ok" -eq 1 ] && echo ok || echo failed).  See $results_dir on optiplex."
      else
        notify high "nix-autobuild: FAILED" \
          "x86_64 build failed for $update_summary -- not publishing. See $results_dir/x86_64-$date_stamp.json on optiplex."
        exit 1
      fi
    '';
  };
in
{
  options.services.nixAutobuild = {
    enable = mkEnableOption "weekly flake-lock refresh, verified build, and cache publish";

    repoUrl = mkOption {
      type = types.str;
      default = "git@github.com:knoc-off/nixos.git";
      description = "git+ssh remote the autobuild clone tracks and pushes the `built` branch to.";
    };

    branch = mkOption {
      type = types.str;
      default = "built";
      description = "Branch force-pushed with the verified flake.lock after a successful build.";
    };

    stateDir = mkOption {
      type = types.path;
      default = "/var/lib/nix-autobuild";
      description = "Where the working clone, gcroots, and result files live.";
    };

    deployKeyFile = mkOption {
      type = types.path;
      description = ''
        Path (sops secret) to an ed25519 private key with push access to
        `repoUrl`. Registered as a GitHub deploy key on knoc-off/nixos; if any
        flake input is a private repo (e.g. minecraft-modpack), the same
        public key needs adding as a deploy key there too, since GitHub deploy
        keys are per-repository.
      '';
    };

    ntfyTokenFile = mkOption {
      type = types.path;
      description = "Path (sops secret) to an ntfy token with write access to ntfyTopic.";
    };

    ntfyUrl = mkOption {
      type = types.str;
      default = "https://ntfy.niko.ink";
      description = "Base URL of the ntfy server (no trailing slash).";
    };

    ntfyTopic = mkOption {
      type = types.str;
      default = "nixbuild";
      description = "ntfy topic for build results.";
    };

    evalWorkers = mkOption {
      type = types.int;
      # nix-fast-build defaults to nproc; on the i5-10500 (12 threads) at the
      # default 4096 MiB/worker that is a 48 GB ceiling against 32 GB of RAM.
      default = 4;
      description = "nix-fast-build --eval-workers.";
    };

    evalMaxMemoryMiB = mkOption {
      type = types.int;
      default = 3072;
      description = "nix-fast-build --eval-max-memory-size, per worker.";
    };

    keepGenerations = mkOption {
      type = types.int;
      default = 8;
      description = "Dated gcroot generations to retain (roughly weeks, at the default weekly schedule).";
    };

    onCalendar = mkOption {
      type = types.str;
      default = "weekly";
      description = "systemd OnCalendar expression for the automatic run.";
    };
  };

  config = mkIf cfg.enable {
    environment.systemPackages = [
      runner
      # Targeted, on-demand version: `nix-autobuild-now hyprland noctalia`.
      # Runs the identical script outside the timer's schedule, as a
      # transient unit so it's still visible to `systemctl status`/journalctl
      # and still gets the LoadCredential secrets -- ad hoc invocation
      # shouldn't mean weaker credential handling than the scheduled one.
      (pkgs.writeShellApplication {
        name = "nix-autobuild-now";
        runtimeInputs = [ pkgs.systemd ];
        text = ''
          exec systemd-run \
            --unit="nix-autobuild-manual-$(date +%s)" \
            --collect --pty --wait --same-dir \
            -p Type=oneshot \
            -p 'LoadCredential=deploy-key:${cfg.deployKeyFile}' \
            -p 'LoadCredential=ntfy-token:${cfg.ntfyTokenFile}' \
            ${getExe runner} "$@"
        '';
      })
    ];

    systemd.services.nix-autobuild = {
      description = "Update flake inputs, build cacheJobs, publish to ${cfg.branch}";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = getExe runner;
        StateDirectory = "nix-autobuild";
        LoadCredential = [
          "deploy-key:${cfg.deployKeyFile}"
          "ntfy-token:${cfg.ntfyTokenFile}"
        ];

        # Runs as root deliberately (see header): it talks to the nix daemon
        # and to git/ssh, neither of which is a privilege gain either way.
        NoNewPrivileges = true;
        ProtectHome = true;
        PrivateTmp = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
        RestrictNamespaces = true;
        LockPersonality = true;
      };
    };

    systemd.timers.nix-autobuild = {
      description = "Weekly nix-autobuild run";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = cfg.onCalendar;
        Persistent = true;
        RandomizedDelaySec = "1h";
      };
    };
  };
}

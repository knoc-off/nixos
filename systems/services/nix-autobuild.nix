# Weekly (or on-demand) refresh of the flake's lockfile, verified by building
# everything cacheJobs names, and published to the `built` branch. See the
# repo-root discussion in nix-cache.nix for why this exists: this is the half
# that keeps optiplex's cache actually current.
#
# The publish gate is deliberately partial. Both architectures are always
# built, every attr is attempted, and only the per-host `toplevel/*` attrs are
# blocking -- a broken ad hoc package leaves the lock publishable, because a
# package that any host actually installs is inside that host's closure and
# fails its toplevel anyway. Everything that did get realised stays in the
# store and is served regardless, so a red run still warms the cache.
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
  self,
  ...
}:
let
  inherit (lib)
    escapeShellArg
    getExe
    getExe'
    mkEnableOption
    mkIf
    mkOption
    types
    ;

  cfg = config.services.nixAutobuild;

  nix = getExe' config.nix.package "nix";

  # The toplevel attrs that must build before a lock is publishable, derived
  # from flake.nix's host table rather than restated here. Anything else in
  # cacheJobs (ad hoc packages, devShell inputs) may fail without blocking the
  # publish: if a package actually matters to a host it is already inside that
  # host's closure and fails the toplevel with it.
  requiredAttrs = lib.mapAttrsToList (
    hostname: system: "${system}\ttoplevel/${hostname}"
  ) self.hostSystems;

  requiredFile = pkgs.writeText "nix-autobuild-required-attrs" (
    lib.concatMapStrings (line: line + "\n") requiredAttrs
  );

  # GitHub's published ssh-ed25519 host key (see
  # https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/githubs-ssh-key-fingerprints).
  # Getting this wrong only fails closed (git over ssh refuses to connect), so
  # pinning it here -- rather than trusting whatever a first connection sees --
  # is strictly safer than TOFU. Worth reconfirming against GitHub's docs at
  # bootstrap time regardless.
  githubKnownHost = "github.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl";

  # Reduces a run's per-arch result JSON to a publish verdict. Kept in Python
  # rather than grep/jq because the interesting fields are nested and the error
  # strings are multi-line JSON-escaped blobs -- line-oriented tools read those
  # as data and silently miscount.
  #
  # nix-fast-build emits one record per attr per phase (EVAL then BUILD), so an
  # attr is only genuinely fine if no phase reports failure for it; checking
  # just the BUILD records would count an attr that never got past EVAL as
  # absent rather than broken.
  gate = pkgs.writers.writePython3 "nix-autobuild-gate" { } ''
    """Read nix-fast-build result JSONs, decide whether the lock is publishable.

    argv: <required-file> <arch>=<results.json> [<arch>=<results.json> ...]

    Writes a human summary to stdout. Exits 0 if every required attr succeeded,
    1 otherwise.
    """
    import json
    import sys

    required = set()
    with open(sys.argv[1]) as fh:
        for line in fh:
            if line.strip():
                arch, attr = line.rstrip("\n").split("\t")
                required.add((arch, attr))

    failed = {}
    seen = set()

    for spec in sys.argv[2:]:
        arch, _, path = spec.partition("=")
        try:
            with open(path) as fh:
                results = json.load(fh).get("results", [])
        except (OSError, json.JSONDecodeError) as exc:
            # A missing or truncated result file means the run died before
            # writing it. Treat every attr for that arch as unproven rather
            # than letting an unreadable file read as "nothing failed".
            print(f"{arch}: unreadable result file ({exc})")
            for key in required:
                if key[0] == arch:
                    failed[key] = "no results"
            continue

        for record in results:
            attr = record.get("attr")
            if attr is None:
                continue
            seen.add((arch, attr))
            if not record.get("success", False):
                phase = record.get("type", "?")
                failed.setdefault((arch, attr), phase)

    # An attr that was required but never appeared in any phase did not
    # silently pass -- it was never evaluated, which is itself a failure.
    for key in required:
        if key not in seen:
            failed.setdefault(key, "missing")

    required_failures = sorted(k for k in failed if k in required)
    other_failures = sorted(k for k in failed if k not in required)


    def fmt(keys):
        return ", ".join(
            f"{arch}:{attr} ({failed[(arch, attr)]})" for arch, attr in keys
        )


    if other_failures:
        print(f"non-blocking failures: {fmt(other_failures)}")

    if required_failures:
        print(f"BLOCKING: {fmt(required_failures)}")
        sys.exit(1)

    print(f"all {len(required)} required toplevels ok")
  '';

  runner = pkgs.writeShellApplication {
    name = "nix-autobuild-run";
    runtimeInputs = [
      pkgs.git
      pkgs.openssh
      pkgs.nix-fast-build
      pkgs.nix-eval-jobs
      pkgs.curl
      pkgs.coreutils
    ];
    text = ''
      state_dir=${escapeShellArg cfg.stateDir}
      repo_dir="$state_dir/nixos"
      gcroots_dir="$state_dir/gcroots"
      known_hosts="$state_dir/known_hosts"
      date_stamp=$(date +%Y%m%d-%H%M%S)

      # One directory per run, holding both arches' out-links and result JSONs.
      # nix-fast-build appends "-<attr>" to --out-link, and attrs contain
      # slashes ("toplevel/framework13", "noctalia/bluetooth"), so the link
      # names are neither predictable nor flat. Giving the run its own
      # directory means retention never has to parse them: the whole
      # generation is one rm -rf, and nested attr directories stay contained.
      run_dir="$gcroots_dir/$date_stamp"
      mkdir -p "$run_dir"

      # ProtectHome=true on the systemd service makes /root a read-only empty
      # mount, and this runs as root with no HOME override -- nix then fails
      # trying to create $HOME/.cache/nix/fetcher-locks. Point it at the state
      # dir instead, which is writable and persists between runs either way.
      export HOME="$state_dir"

      # git refuses to commit without an identity, and it will not find one:
      # there is no global config under the redirected HOME, and the fallback
      # from hostname/username is rejected as auto-detected
      # ("root@optiplex.(none)"). Set it in the environment rather than
      # writing a .gitconfig -- the state dir is disposable, and the commits
      # produced here are machine-generated lock bumps, not authored work.
      export GIT_AUTHOR_NAME=${escapeShellArg cfg.committerName}
      export GIT_AUTHOR_EMAIL=${escapeShellArg cfg.committerEmail}
      export GIT_COMMITTER_NAME=${escapeShellArg cfg.committerName}
      export GIT_COMMITTER_EMAIL=${escapeShellArg cfg.committerEmail}

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
      # reset before checkout, not after. A run that dies between `nix flake
      # update` and the commit leaves flake.lock modified; once origin/main
      # moves, `checkout -B` then refuses to overwrite it and every subsequent
      # run aborts here having done nothing, permanently, until someone logs
      # in. Discarding is always right: the working tree is disposable state,
      # rebuilt from origin/main and a fresh `flake update` on every run.
      git reset --hard origin/main
      git checkout -B autobuild-work origin/main
      git clean -fdx

      # No args: update every input. With args: update just those, e.g.
      # `nix-autobuild-now hyprland noctalia`. Same subcommand either way --
      # `nix flake update inputs...` is the current interface (the older
      # `nix flake lock --update-input` form still works but is legacy).
      #
      # --accept-flake-config because flake.nix carries a nixConfig block, and
      # without it nix stops to ask interactively -- which in a Type=oneshot
      # unit with no TTY is a hang, not a failure. Answering the prompt by hand
      # once caches it under $HOME, but that is undeclared state inside a
      # StateDirectory: it vanishes on a state reset and never exists on a
      # fresh host. Nothing is actually granted here, since the substituters
      # and keys that block names are already trusted system-wide in
      # modules/nix.nix.
      ${escapeShellArg nix} flake update --accept-flake-config "$@"
      if [ "$#" -eq 0 ]; then
        update_summary="all inputs"
      else
        update_summary="$*"
      fi

      # Both arches run unconditionally. Gating aarch64 on x86 success meant
      # the Pi -- the host least able to build for itself -- was never built at
      # all while any x86 attr was broken. The arches share no build inputs
      # that would make one's failure predictive of the other's.
      build_arch() {
        local arch="$1"
        nix-fast-build \
          --nix ${escapeShellArg nix} \
          --flake ".#cacheJobs.$arch" \
          --systems "$arch" \
          --skip-cached \
          --no-nom \
          --retries 1 \
          --option accept-flake-config true \
          --eval-workers ${toString cfg.evalWorkers} \
          --eval-max-memory-size ${toString cfg.evalMaxMemoryMiB} \
          --out-link "$run_dir/$arch" \
          --result-file "$run_dir/$arch.json" \
          || true
      }

      build_arch x86_64-linux
      build_arch aarch64-linux

      # Retention: keep the last N dated run directories. Older ones lose their
      # out-links, so nix.gc reclaims the store paths they alone were pinning;
      # their result JSONs go with them, since they only describe builds we can
      # no longer inspect. The glob only matches dated names, so the
      # `published` symlink set below is never a retention candidate.
      for old_run in $(
        printf '%s\n' "$gcroots_dir"/[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]-[0-9][0-9][0-9][0-9][0-9][0-9] \
          | sort -r \
          | tail -n "+$((${toString cfg.keepGenerations} + 1))"
      ); do
        rm -rf "''${old_run:?}"
      done

      # Publish gate: only the per-host toplevels are blocking. A failed ad hoc
      # package does not stop hosts from switching -- if it were actually
      # installed somewhere, it would have failed that host's toplevel too.
      verdict_file="$run_dir/verdict.txt"
      gate_ok=1
      ${gate} ${escapeShellArg requiredFile} \
        "x86_64-linux=$run_dir/x86_64-linux.json" \
        "aarch64-linux=$run_dir/aarch64-linux.json" \
        > "$verdict_file" 2>&1 || gate_ok=0
      verdict=$(cat "$verdict_file")

      if [ "$gate_ok" -eq 1 ]; then
        git add flake.lock
        # No --allow-empty: `built` should only move when the lock actually
        # changed, so its history stays a log of real bumps and clients can
        # tell "nothing to do" from "a new lock landed" by rev alone.
        if git diff --cached --quiet; then
          notify low "nix-autobuild: no change" \
            "$update_summary produced no lock change; $verdict"
          exit 0
        fi
        git commit -m "autobuild: $date_stamp ($update_summary)"

        # Pin before publishing, not after. These out-links are what keeps the
        # published closure alive across nix.gc, independently of the dated
        # rotation above -- so if the push were to happen first and this were
        # to fail, `built` would name a closure that gc is free to delete.
        # cp -a copies the symlinks themselves, giving `published` its own
        # roots rather than a reference to the run dir that retention rotates.
        rm -rf "''${gcroots_dir:?}/published"
        cp -a --reflink=auto "$run_dir" "$gcroots_dir/published"

        git push --force origin "HEAD:${cfg.branch}"

        notify default "nix-autobuild: published" \
          "updated: $update_summary. $verdict. See $run_dir on optiplex."
      else
        notify high "nix-autobuild: FAILED" \
          "$update_summary not published. $verdict. See $run_dir on optiplex."
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

    committerName = mkOption {
      type = types.str;
      default = "nix-autobuild";
      description = "Author and committer name on the generated lock-bump commits.";
    };

    committerEmail = mkOption {
      type = types.str;
      default = "nix-autobuild@localhost";
      description = ''
        Author and committer email on the generated lock-bump commits. Never
        receives mail -- it exists because git will not commit without one.
      '';
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
        #
        # RestrictNamespaces and ProtectKernelTunables are deliberately absent.
        # root is a trusted-user and NIX_REMOTE is unset, so nix builds
        # in-process inside this unit rather than handing work to nix-daemon --
        # and the build sandbox is itself made of user/mount namespaces. Either
        # setting makes every sandboxed build fail with "this system does not
        # support the kernel namespaces that are required for sandboxing",
        # which is a confusing way to say the service was hardened against its
        # own job. Both were confirmed to break it, and the set kept below
        # confirmed not to, by running an identical trivial derivation under
        # systemd-run with each option toggled.
        NoNewPrivileges = true;
        ProtectHome = true;
        PrivateTmp = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
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

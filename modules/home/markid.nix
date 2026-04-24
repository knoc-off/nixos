# markid — long-running daemon that syncs a directory of markdown cards
# with Anki via AnkiConnect.
#
# This module can also optionally run:
#   * Anki in headless mode (xvfb-run) with the AnkiConnect add-on
#     pre-installed declaratively, so markid has something to talk to.
#   * A local anki-sync-server, so your devices (phone, laptop) sync to
#     this host instead of AnkiWeb. The headless Anki syncs to it too.
#   * A systemd timer that periodically does `git fetch && git reset --hard`
#     against the cards repo. markid's inotify watch picks up the resulting
#     file changes automatically.
#
# Topology:
#
#   devices  ⇄  anki-sync-server (local)  ⇄  xvfb anki  ←  markid  ←  cards dir
#                                                                     ↑
#                                                     git-poll timer ─┘
{
  self,
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.services.markid;
  tomlFormat = pkgs.formats.toml {};

  # Anki sync-server settings are pushed to xvfb Anki via a meta/profile
  # config file. See `anki-prefs.nix` comment below for the file layout.
  syncBaseUrl = "http://${cfg.anki.syncServer.host}:${toString cfg.anki.syncServer.port}/";

  markidConfig = tomlFormat.generate "markid-config.toml" cfg.settings;

  # Build an Anki wrapper with AnkiConnect pre-installed so Anki itself
  # doesn't need runtime write access to copy addon files into the profile.
  ankiWithAddons =
    if cfg.anki.enable
    then cfg.anki.package.withAddons (with pkgs.ankiAddons; [anki-connect])
    else cfg.anki.package;

  # Shell script that does one git-poll cycle. Written to the store and
  # invoked by the systemd oneshot.
  gitPollScript = pkgs.writeShellApplication {
    name = "markid-git-poll";
    runtimeInputs = [pkgs.git pkgs.openssh pkgs.coreutils];
    text = ''
      set -euo pipefail
      CARDS_DIR=${escapeShellArg cfg.gitPoll.cardsDir}
      REPO=${escapeShellArg cfg.gitPoll.repo}
      BRANCH=${escapeShellArg cfg.gitPoll.branch}
      mkdir -p "$(dirname "$CARDS_DIR")"
      if [ ! -d "$CARDS_DIR/.git" ]; then
        echo "markid-git-poll: cloning $REPO into $CARDS_DIR"
        git clone --branch "$BRANCH" "$REPO" "$CARDS_DIR"
      fi
      cd "$CARDS_DIR"
      echo "markid-git-poll: fetching"
      git fetch --prune origin
      echo "markid-git-poll: resetting to origin/$BRANCH"
      git reset --hard "origin/$BRANCH"
    '';
  };
in {
  options.services.markid = {
    enable = mkEnableOption "markid — markdown-to-Anki sync daemon";

    package = mkOption {
      type = types.package;
      default = self.packages.${pkgs.stdenv.hostPlatform.system}.marki;
      description = "The markid package to use.";
    };

    settings = mkOption {
      type = tomlFormat.type;
      default = {};
      description = ''
        Config written to `~/.config/markid/config.toml`.

        Keys:
          - `cards_dir` (string, required): absolute path to the directory of `.md` cards
          - `anki_endpoint` (string): default `http://127.0.0.1:8765`
          - `sync_interval` (string or int): e.g. `"5m"` or `300`
          - `debounce_ms` (int): default `250`
          - `ankiweb_sync` (bool): default `true` — call AnkiConnect `sync` before/after each cycle
      '';
      example = literalExpression ''
        {
          cards_dir = "/var/lib/markid/cards";
          sync_interval = "5m";
        }
      '';
    };

    logLevel = mkOption {
      type = types.str;
      default = "info";
      description = "Value for `RUST_LOG` env var passed to the daemon.";
    };

    # --------------------------------------------------------------------
    # Anki-on-this-host
    # --------------------------------------------------------------------
    anki = {
      enable = mkEnableOption "run Anki (xvfb) + AnkiConnect on this host";

      package = mkOption {
        type = types.package;
        default = pkgs.anki;
        description = "Anki package. Will have AnkiConnect added via `withAddons`.";
      };

      profile = mkOption {
        type = types.str;
        default = "User 1";
        description = "Anki profile name to load.";
      };

      profileDir = mkOption {
        type = types.str;
        default = "%h/.local/share/Anki2";
        description = ''
          Base directory Anki uses for its profiles. This is Anki's default;
          leave as-is unless you really need to move it.
        '';
      };

      ankiConnectPort = mkOption {
        type = types.port;
        default = 8765;
        description = "Port AnkiConnect binds on localhost.";
      };

      # --- self-hosted sync server, nested under `anki`
      syncServer = {
        enable = mkEnableOption "self-hosted anki-sync-server on this host";

        package = mkOption {
          type = types.package;
          default = pkgs.anki-sync-server;
          description = "anki-sync-server package.";
        };

        host = mkOption {
          type = types.str;
          default = "127.0.0.1";
          description = ''
            Interface to bind to. Use `127.0.0.1` and put a TLS reverse
            proxy (caddy/nginx) in front for remote device access;
            `0.0.0.0` if you know what you're doing.
          '';
        };

        port = mkOption {
          type = types.port;
          default = 27701;
          description = "Port to bind the sync server on.";
        };

        baseDir = mkOption {
          type = types.str;
          default = "%h/.local/share/anki-sync-server";
          description = "Data directory the sync server stores user collections in.";
        };

        usernameFile = mkOption {
          type = types.path;
          description = ''
            Path to a file containing the sync username (first line only).
            Typically a sops/agenix-managed secret.
          '';
        };

        passwordFile = mkOption {
          type = types.path;
          description = ''
            Path to a file containing the sync password (first line only).
            Typically a sops/agenix-managed secret.
          '';
        };

        pointXvfbAnki = mkOption {
          type = types.bool;
          default = true;
          description = ''
            If true, write the xvfb Anki's profile prefs so that its sync
            target is this local sync server rather than AnkiWeb.
          '';
        };
      };
    };

    # --------------------------------------------------------------------
    # git poll
    # --------------------------------------------------------------------
    gitPoll = {
      enable = mkEnableOption "periodic git pull into the cards directory";

      repo = mkOption {
        type = types.str;
        description = ''
          Git URL to clone/pull from. For a private repo, use the HTTPS form
          and supply `tokenFile` — the token is injected via a git credential
          helper so it never lands in ps output.
        '';
        example = "https://github.com/knoff/cards.git";
      };

      branch = mkOption {
        type = types.str;
        default = "main";
      };

      cardsDir = mkOption {
        type = types.str;
        description = ''
          Absolute path the repo will be cloned into / reset in. Should
          match `services.markid.settings.cards_dir`.
        '';
      };

      interval = mkOption {
        type = types.str;
        default = "5m";
        description = "Timer cadence, in systemd's `OnUnitActiveSec` syntax.";
      };

      tokenFile = mkOption {
        type = types.nullOr types.path;
        default = null;
        description = ''
          Optional HTTPS PAT file (sops/agenix). Used via a git credential
          helper so it never appears in the URL or in ps output.
        '';
      };
    };
  };

  config = mkIf cfg.enable (mkMerge [
    # --- markid daemon itself
    {
      home.packages = [cfg.package];

      xdg.configFile."markid/config.toml".source = markidConfig;

      systemd.user.services.markid = {
        Unit = {
          Description = "markid — markdown to Anki sync daemon";
          After = ["network.target"] ++ optional cfg.anki.enable "anki-desktop.service";
          Wants = optional cfg.anki.enable "anki-desktop.service";
        };

        Service = {
          ExecStart = "${getExe cfg.package} watch";
          Environment = [
            "RUST_LOG=${cfg.logLevel}"
            "MARKID_CONFIG=%h/.config/markid/config.toml"
          ];
          Restart = "on-failure";
          RestartSec = 5;
        };

        Install.WantedBy = ["default.target"];
      };
    }

    # --- Anki (xvfb) + declarative AnkiConnect addon
    (mkIf cfg.anki.enable {
      home.packages = [ankiWithAddons pkgs.xvfb-run];

      # Declarative AnkiConnect config: bind localhost:<port>.
      # AnkiConnect reads this file at startup; changing it requires an
      # anki-desktop restart, which the systemd unit handles via
      # `Restart=on-failure` + manual `systemctl --user restart` on config change.
      xdg.configFile."Anki2/addons21/anki-connect/config.json".text = builtins.toJSON {
        webBindAddress = "127.0.0.1";
        webBindPort = cfg.anki.ankiConnectPort;
        apiLogPath = null;
        apiPollInterval = 25;
      };

      systemd.user.services.anki-desktop = {
        Unit = {
          Description = "Anki (headless via xvfb-run) with AnkiConnect";
          After = ["network.target"] ++ optional cfg.anki.syncServer.enable "anki-sync-server.service";
          Wants = optional cfg.anki.syncServer.enable "anki-sync-server.service";
        };

        Service = {
          ExecStart = "${pkgs.xvfb-run}/bin/xvfb-run -a ${getExe ankiWithAddons} -b ${cfg.anki.profileDir} -p ${escapeShellArg cfg.anki.profile}";
          Restart = "on-failure";
          RestartSec = 5;
        };

        Install.WantedBy = ["default.target"];
      };
    })

    # --- anki-sync-server
    (mkIf (cfg.anki.enable && cfg.anki.syncServer.enable) {
      systemd.user.services.anki-sync-server = let
        ss = cfg.anki.syncServer;
      in {
        Unit = {
          Description = "Self-hosted anki-sync-server";
          After = ["network.target"];
        };

        Service = {
          # Env vars: SYNC_BASE for data dir, SYNC_HOST / SYNC_PORT for
          # binding, SYNC_USER1=user:pass for the single-user credentials.
          # The user:pass pair is assembled at exec time from the secret
          # files so the password never ends up in the unit file.
          ExecStart = pkgs.writeShellScript "anki-sync-server-start" ''
            set -eu
            USER="$(head -n1 ${escapeShellArg ss.usernameFile})"
            PASS="$(head -n1 ${escapeShellArg ss.passwordFile})"
            export SYNC_USER1="$USER:$PASS"
            export SYNC_HOST=${escapeShellArg ss.host}
            export SYNC_PORT=${toString ss.port}
            export SYNC_BASE=${escapeShellArg ss.baseDir}
            mkdir -p "$SYNC_BASE"
            exec ${getExe ss.package}
          '';
          Restart = "on-failure";
          RestartSec = 5;
        };

        Install.WantedBy = ["default.target"];
      };

      # Point the xvfb Anki profile at the local sync server by writing
      # its `meta` preference file. Anki stores this in the profile dir
      # at `<profileDir>/<profile>/meta` (as JSON since 25.x).
      #
      # We use home.activation because the file lives inside a directory
      # Anki *also* writes to, so we can't manage it as a read-only
      # xdg.configFile symlink.
      home.activation.markidAnkiSyncConfig = mkIf cfg.anki.syncServer.pointXvfbAnki (
        lib.hm.dag.entryAfter ["writeBoundary"] ''
          # Expand %h -> $HOME manually since activation scripts run as the user.
          PROFILE_DIR="${cfg.anki.profileDir}"
          PROFILE_DIR="''${PROFILE_DIR//%h/$HOME}"
          PROFILE_NAME=${escapeShellArg cfg.anki.profile}
          mkdir -p "$PROFILE_DIR/$PROFILE_NAME"
          # Write a tiny meta.json that Anki reads on startup. It will
          # merge this with its own defaults on first load.
          cat > "$PROFILE_DIR/$PROFILE_NAME/markid-sync.json" <<EOF
          {
            "custom_sync_url": ${builtins.toJSON syncBaseUrl}
          }
          EOF
        ''
      );
    })

    # --- git poll timer
    (mkIf cfg.gitPoll.enable {
      # Write a git credential helper that `cat`s the token file, so git
      # can authenticate to HTTPS remotes without the token ever being in
      # the remote URL or in process argv.
      xdg.configFile = mkIf (cfg.gitPoll.tokenFile != null) {
        "markid/git-credential-helper".source = pkgs.writeShellScript "markid-git-credential" ''
          set -eu
          # git invokes credential helpers with `get`; echo the token on stdout.
          if [ "$1" != "get" ]; then exit 0; fi
          TOKEN="$(head -n1 ${escapeShellArg cfg.gitPoll.tokenFile})"
          echo "username=x-access-token"
          echo "password=$TOKEN"
        '';
      };

      systemd.user.services.markid-git-poll = {
        Unit = {
          Description = "markid: periodic git fetch + reset into cards dir";
          After = ["network-online.target"];
          Wants = ["network-online.target"];
        };

        Service =
          {
            Type = "oneshot";
            ExecStart = "${gitPollScript}/bin/markid-git-poll";
          }
          // (
            if cfg.gitPoll.tokenFile != null
            then {
              Environment = [
                # Wire the credential helper for this service's git invocations.
                "GIT_CONFIG_COUNT=1"
                "GIT_CONFIG_KEY_0=credential.helper"
                "GIT_CONFIG_VALUE_0=%h/.config/markid/git-credential-helper"
              ];
            }
            else {}
          );
      };

      systemd.user.timers.markid-git-poll = {
        Unit.Description = "markid: git-poll timer";
        Timer = {
          OnBootSec = "30s";
          OnUnitActiveSec = cfg.gitPoll.interval;
          Persistent = true;
        };
        Install.WantedBy = ["timers.target"];
      };
    })
  ]);
}

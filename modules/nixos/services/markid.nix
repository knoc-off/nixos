# markid — system-level NixOS module for a headless server.
#
# Runs the full topology on one host:
#
#   devices  ⇄  anki-sync-server  ⇄  anki (xvfb)  ⇄  markid  ←  cards dir
#                                                                  ↑
#                                                     git-poll  ───┘
#
# Everything runs as a single dedicated system user (`markid`). The xvfb
# Anki syncs to the local sync server (not AnkiWeb); markid talks to
# AnkiConnect on localhost; git-poll keeps the cards dir up to date from
# a git remote.
#
# This module is the system-level analogue of modules/home/markid.nix.
# Use the system module on headless boxes; use the home module on
# graphical machines where Anki is a regular desktop app.
{
  config,
  lib,
  pkgs,
  self,
  ...
}:
with lib; let
  cfg = config.services.markid;

  tomlFormat = pkgs.formats.toml {};
  markidConfig = tomlFormat.generate "markid-config.toml" cfg.settings;

  # Anki with AnkiConnect declaratively pre-installed. No runtime write
  # needed into the profile's addons21 dir.
  ankiWithAddons =
    if cfg.anki.enable
    then cfg.anki.package.withAddons (with pkgs.ankiAddons; [anki-connect])
    else cfg.anki.package;

  # AnkiConnect config file — copied into the profile's addon dir on
  # every startup, replacing whatever was there.
  ankiConnectConfig = pkgs.writeText "anki-connect-config.json" (builtins.toJSON {
    webBindAddress = "127.0.0.1";
    webBindPort = cfg.anki.ankiConnectPort;
    apiLogPath = null;
    apiPollInterval = 25;
  });

  syncBaseUrl = "http://${cfg.anki.syncServer.host}:${toString cfg.anki.syncServer.port}/";

  # One-shot git poll script. No writeback from markid -> git, by design.
  gitPollScript = pkgs.writeShellApplication {
    name = "markid-git-poll";
    runtimeInputs = [pkgs.git pkgs.openssh pkgs.coreutils];
    text = ''
      set -euo pipefail
      CARDS_DIR=${escapeShellArg cfg.settings.cards_dir}
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

  # Credential helper used when an HTTPS token file is configured. Git
  # invokes `helper get` to resolve credentials; we echo username+password
  # from the secret file. Never appears in process argv.
  gitCredHelper = pkgs.writeShellScript "markid-git-credential" ''
    set -eu
    if [ "''${1-}" != "get" ]; then exit 0; fi
    TOKEN="$(head -n1 ${escapeShellArg (toString cfg.gitPoll.tokenFile)})"
    echo "username=x-access-token"
    echo "password=$TOKEN"
  '';
in {
  options.services.markid = {
    enable = mkEnableOption "markid — markdown-to-Anki sync daemon";

    package = mkOption {
      type = types.package;
      default = self.packages.${pkgs.stdenv.hostPlatform.system}.marki;
      description = "markid package.";
    };

    user = mkOption {
      type = types.str;
      default = "markid";
      description = "System user under which everything in this module runs.";
    };

    group = mkOption {
      type = types.str;
      default = "markid";
    };

    stateDir = mkOption {
      type = types.str;
      default = "/var/lib/markid";
      description = ''
        Root for all mutable state (cards dir, Anki profile, sync server
        data, git clone). Created as `$user:$group` 0750.
      '';
    };

    settings = mkOption {
      type = tomlFormat.type;
      default = {};
      description = ''
        Contents of `markid/config.toml`. Must include `cards_dir`.
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
      description = "RUST_LOG value.";
    };

    # -----------------------------------------------------------------
    # Anki (xvfb)
    # -----------------------------------------------------------------
    anki = {
      enable = mkEnableOption "run headless Anki (xvfb-run) with AnkiConnect";

      package = mkOption {
        type = types.package;
        default = pkgs.anki;
      };

      profile = mkOption {
        type = types.str;
        default = "User 1";
        description = "Anki profile name to load.";
      };

      ankiConnectPort = mkOption {
        type = types.port;
        default = 8765;
      };

      # ---- self-hosted anki-sync-server
      syncServer = {
        enable = mkEnableOption "self-hosted anki-sync-server";

        package = mkOption {
          type = types.package;
          default = pkgs.anki-sync-server;
        };

        host = mkOption {
          type = types.str;
          default = "127.0.0.1";
          description = ''
            Interface to bind to. Default `127.0.0.1`; front with a TLS
            reverse proxy (e.g. caddy) for remote device access.
          '';
        };

        port = mkOption {
          type = types.port;
          default = 27701;
        };

        usernameFile = mkOption {
          type = types.path;
          description = "Path (sops secret) to a file whose first line is the sync username.";
        };

        passwordFile = mkOption {
          type = types.path;
          description = "Path (sops secret) to a file whose first line is the sync password.";
        };

        pointXvfbAnki = mkOption {
          type = types.bool;
          default = true;
          description = ''
            If true, write a hint file into the xvfb Anki's profile
            pointing it at the local sync server. Note that Anki's sync
            URL still has to be set interactively in the GUI the first
            time; once set, it persists in the profile's prefs.db.
          '';
        };
      };
    };

    # -----------------------------------------------------------------
    # git poll
    # -----------------------------------------------------------------
    gitPoll = {
      enable = mkEnableOption "periodic `git fetch && git reset --hard` into cards_dir";

      repo = mkOption {
        type = types.str;
        description = "Git URL to clone/pull. HTTPS form expected when using tokenFile.";
        example = "https://github.com/you/cards.git";
      };

      branch = mkOption {
        type = types.str;
        default = "main";
      };

      interval = mkOption {
        type = types.str;
        default = "5m";
        description = "systemd `OnUnitActiveSec` syntax.";
      };

      tokenFile = mkOption {
        type = types.nullOr types.path;
        default = null;
        description = ''
          Sops/agenix-managed PAT for HTTPS access. First line is the
          token. Fed to git via a credential helper so it never appears
          in argv, env, or the URL.
        '';
      };
    };
  };

  config = mkIf cfg.enable (mkMerge [
    # ---------- user/group + state dirs ----------
    {
      users.users.${cfg.user} = {
        isSystemUser = true;
        group = cfg.group;
        home = cfg.stateDir;
        createHome = true;
        description = "markid daemon";
      };
      users.groups.${cfg.group} = {};

      # tmpfiles to pre-create the layout with right ownership.
      systemd.tmpfiles.rules = [
        "d ${cfg.stateDir}                     0750 ${cfg.user} ${cfg.group} - -"
        "d ${cfg.stateDir}/config              0750 ${cfg.user} ${cfg.group} - -"
        "d ${cfg.stateDir}/config/markid       0750 ${cfg.user} ${cfg.group} - -"
      ];

      # Drop the markid config into the state dir so the daemon can read it.
      environment.etc."markid/config.toml".source = markidConfig;

      environment.systemPackages = [cfg.package];
    }

    # ---------- markid daemon ----------
    {
      systemd.services.markid = {
        description = "markid — markdown to Anki sync daemon";
        after = ["network.target"] ++ optional cfg.anki.enable "anki-desktop.service";
        wants = optional cfg.anki.enable "anki-desktop.service";
        wantedBy = ["multi-user.target"];

        environment = {
          RUST_LOG = cfg.logLevel;
          MARKID_CONFIG = "/etc/markid/config.toml";
        };

        serviceConfig = {
          User = cfg.user;
          Group = cfg.group;
          ExecStart = "${getExe cfg.package} watch";
          Restart = "on-failure";
          RestartSec = 5;

          # Hardening — modest, since we need network (AnkiConnect) and FS writes.
          NoNewPrivileges = true;
          ProtectSystem = "strict";
          ProtectHome = true;
          ReadWritePaths = [cfg.stateDir];
          PrivateTmp = true;
          ProtectKernelTunables = true;
          ProtectKernelModules = true;
          ProtectControlGroups = true;
          RestrictSUIDSGID = true;
          RestrictNamespaces = true;
          LockPersonality = true;
          MemoryDenyWriteExecute = false; # Rust/syntect does some JIT-adjacent work via regex
        };
      };
    }

    # ---------- Anki (xvfb) + AnkiConnect ----------
    (mkIf cfg.anki.enable {
      systemd.tmpfiles.rules = [
        "d ${cfg.stateDir}/Anki2                                       0750 ${cfg.user} ${cfg.group} - -"
        "d ${cfg.stateDir}/Anki2/addons21                              0750 ${cfg.user} ${cfg.group} - -"
        "d ${cfg.stateDir}/Anki2/addons21/anki-connect                 0750 ${cfg.user} ${cfg.group} - -"
        "L+ ${cfg.stateDir}/Anki2/addons21/anki-connect/config.json    -    -           -            - ${ankiConnectConfig}"
      ];

      systemd.services.anki-desktop = {
        description = "Anki (headless via xvfb-run) with AnkiConnect";
        after =
          ["network.target"]
          ++ optional cfg.anki.syncServer.enable "anki-sync-server.service";
        wants = optional cfg.anki.syncServer.enable "anki-sync-server.service";
        wantedBy = ["multi-user.target"];

        # Anki uses Qt; give it a stable HOME and a virtual X display.
        environment = {
          HOME = cfg.stateDir;
          XDG_DATA_HOME = "${cfg.stateDir}";
          # Qt loudly warns without these on headless boxes.
          QT_QPA_PLATFORM = "xcb";
          DISPLAY = ":99";
          # Anki embeds QtWebEngine (Chromium). On a headless host without
          # GL / user namespaces its sandbox + GPU init will crash the
          # whole process. These flags make it boot reliably on Xvfb.
          QTWEBENGINE_CHROMIUM_FLAGS = "--no-sandbox --disable-gpu --disable-software-rasterizer";
        };

        serviceConfig = {
          User = cfg.user;
          Group = cfg.group;
          # Use Xvfb directly (not xvfb-run) so systemd manages the X server
          # lifetime cleanly and we get a stable DISPLAY.
          ExecStart = pkgs.writeShellScript "anki-desktop-start" ''
            set -eu

            # Under PrivateTmp=true the service gets a fresh /tmp where
            # /tmp/.X11-unix doesn't exist, and Xvfb refuses to create it
            # as non-root (_XSERVTransmkdir error). Pre-create it.
            mkdir -p /tmp/.X11-unix
            chmod 1777 /tmp/.X11-unix || true

            ${pkgs.xorg.xorgserver}/bin/Xvfb :99 -screen 0 1024x768x24 -nolisten tcp &
            XVFB_PID=$!
            trap 'kill $XVFB_PID 2>/dev/null || true' EXIT

            # Wait up to 10s for Xvfb to be ready (socket at /tmp/.X11-unix/X99).
            for i in $(seq 1 100); do
              if [ -S /tmp/.X11-unix/X99 ]; then
                break
              fi
              sleep 0.1
            done
            if [ ! -S /tmp/.X11-unix/X99 ]; then
              echo "anki-desktop: Xvfb did not come up within 10s" >&2
              exit 1
            fi

            exec ${getExe ankiWithAddons} -b ${escapeShellArg "${cfg.stateDir}/Anki2"} -p ${escapeShellArg cfg.anki.profile}
          '';
          Restart = "on-failure";
          RestartSec = 10;
          # PrivateTmp gives Anki its own writable /tmp so we can mkdir
          # /tmp/.X11-unix for Xvfb. Without it, ProtectSystem=strict +
          # ReadWritePaths=/var/lib/markid makes /tmp read-only and Xvfb
          # can't create its Unix domain socket directory.
          PrivateTmp = true;
          ProtectSystem = "strict";
          ProtectHome = true;
          ReadWritePaths = [cfg.stateDir];
        };
      };
    })

    # ---------- anki-sync-server ----------
    (mkIf (cfg.anki.enable && cfg.anki.syncServer.enable) {
      systemd.tmpfiles.rules =
        [
          "d ${cfg.stateDir}/anki-sync-server 0750 ${cfg.user} ${cfg.group} - -"
        ]
        ++ optional cfg.anki.syncServer.pointXvfbAnki
        ''f+ ${cfg.stateDir}/Anki2/${cfg.anki.profile}/markid-sync-url.txt 0640 ${cfg.user} ${cfg.group} - ${syncBaseUrl}'';

      systemd.services.anki-sync-server = let
        ss = cfg.anki.syncServer;
      in {
        description = "Self-hosted anki-sync-server";
        after = ["network.target"];
        wantedBy = ["multi-user.target"];

        serviceConfig = {
          User = cfg.user;
          Group = cfg.group;
          # LoadCredential gives the service read-only access to the secrets
          # at %d/<name> without the files becoming world-readable on disk.
          LoadCredential = [
            "username:${toString ss.usernameFile}"
            "password:${toString ss.passwordFile}"
          ];
          ExecStart = pkgs.writeShellScript "anki-sync-server-start" ''
            set -eu
            USER="$(head -n1 "$CREDENTIALS_DIRECTORY/username")"
            PASS="$(head -n1 "$CREDENTIALS_DIRECTORY/password")"
            export SYNC_USER1="$USER:$PASS"
            export SYNC_HOST=${escapeShellArg ss.host}
            export SYNC_PORT=${toString ss.port}
            export SYNC_BASE=${escapeShellArg "${cfg.stateDir}/anki-sync-server"}
            exec ${getExe ss.package}
          '';
          Restart = "on-failure";
          RestartSec = 5;
          ProtectSystem = "strict";
          ProtectHome = true;
          ReadWritePaths = ["${cfg.stateDir}/anki-sync-server"];
          NoNewPrivileges = true;
          PrivateTmp = true;
        };
      };
    })

    # ---------- git-poll ----------
    (mkIf cfg.gitPoll.enable {
      systemd.services.markid-git-poll = {
        description = "markid: periodic git fetch + reset into cards dir";
        after = ["network-online.target"];
        wants = ["network-online.target"];
        # Not wantedBy: the timer owns activation.

        environment =
          lib.optionalAttrs (cfg.gitPoll.tokenFile != null) {
            GIT_CONFIG_COUNT = "1";
            GIT_CONFIG_KEY_0 = "credential.helper";
            GIT_CONFIG_VALUE_0 = toString gitCredHelper;
          };

        serviceConfig = {
          Type = "oneshot";
          User = cfg.user;
          Group = cfg.group;
          ExecStart = "${gitPollScript}/bin/markid-git-poll";
          ProtectSystem = "strict";
          ProtectHome = true;
          ReadWritePaths = [cfg.stateDir];
          NoNewPrivileges = true;
        };
      };

      systemd.timers.markid-git-poll = {
        description = "markid git-poll timer";
        wantedBy = ["timers.target"];
        timerConfig = {
          OnBootSec = "30s";
          OnUnitActiveSec = cfg.gitPoll.interval;
          Persistent = true;
        };
      };
    })
  ]);
}

# markid — markdown-to-Anki sync daemon (dual-layer)
#
# NixOS side: headless server deployment (dedicated system user, xvfb Anki,
#             anki-sync-server, git-poll). Use on headless boxes.
# HM side:   desktop deployment (user systemd services, xvfb-run Anki,
#             anki-sync-server, git-poll). Use on graphical machines.
{ inputs, self }: let
  markidPkg = system: self.packages.${system}.marki;
  naturalEarthPkg = system: self.packages.${system}.natural-earth-data or null;
in {
  nixos = { config, lib, pkgs, ... }:
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
        default = markidPkg pkgs.stdenv.hostPlatform.system;
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

      naturalEarthData = mkOption {
        type = types.nullOr types.package;
        default = naturalEarthPkg pkgs.stdenv.hostPlatform.system;
        description = ''
          Natural Earth shapefile bundle used by `marki-map` to resolve
          `country/<iso>`, `admin1/<iso>/<name>`, `coastline`, and
          `neighbors/<iso>` feature references in `map` blocks.

          Exposed to the daemon via the `NATURAL_EARTH_DATA` env var.
          Set to `null` to disable; map blocks referencing offline
          features will then fail with a `block failed` stub on the
          rendered card (the daemon never aborts the corpus).
        '';
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

        # ---- AnkiWeb sync timer (decoupled from markid cycles)
        syncTimer = {
          enable = mkEnableOption "periodic AnkiWeb sync via AnkiConnect (decoupled from markid card-push cycles)";

          interval = mkOption {
            type = types.str;
            default = "30m";
            description = "systemd `OnUnitActiveSec` syntax.";
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

          environment =
            {
              RUST_LOG = cfg.logLevel;
              MARKID_CONFIG = "/etc/markid/config.toml";
            }
            // lib.optionalAttrs (cfg.naturalEarthData != null) {
              NATURAL_EARTH_DATA = "${cfg.naturalEarthData}";
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

            # cgroup-local OOM, so anki can't take other services down with it.
            MemoryHigh = "500M";
            MemoryMax = "700M";
            OOMPolicy = "kill";
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

      # ---------- AnkiWeb sync timer ----------
      (mkIf (cfg.anki.enable && cfg.anki.syncTimer.enable) {
        systemd.services.anki-sync = {
          description = "Trigger AnkiWeb sync via AnkiConnect";
          after = ["anki-desktop.service"];

          serviceConfig = {
            Type = "oneshot";
            User = cfg.user;
            Group = cfg.group;
            ExecStart = pkgs.writeShellScript "anki-sync-trigger" ''
              set -eu
              ${pkgs.curl}/bin/curl -sf -X POST \
                "http://127.0.0.1:${toString cfg.anki.ankiConnectPort}" \
                -H "Content-Type: application/json" \
                -d '{"action":"sync","version":6,"params":{}}' \
                --connect-timeout 5 \
                --max-time 120
            '';
            TimeoutStartSec = "180";
            ProtectSystem = "strict";
            ProtectHome = true;
            NoNewPrivileges = true;
            PrivateTmp = true;
          };
        };

        systemd.timers.anki-sync = {
          description = "AnkiWeb sync timer";
          wantedBy = ["timers.target"];
          timerConfig = {
            OnBootSec = "5m";
            OnUnitActiveSec = cfg.anki.syncTimer.interval;
            Persistent = true;
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
  };

  home = { self, config, lib, pkgs, ... }:
  with lib; let
    cfg = config.services.markid;
    tomlFormat = pkgs.formats.toml {};

    # Anki sync-server settings are pushed to xvfb Anki via a meta/profile
    # config file. See `anki-prefs.nix` comment below for the file layout.
    syncBaseUrl = "http://${cfg.anki.syncServer.host}:${toString cfg.anki.syncServer.port}/";

    markidConfig = tomlFormat.generate "markid-config.toml" (
      cfg.settings
      // (if cfg.mediaSources != {} then { media_sources = cfg.mediaSources; } else {})
    );

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
        default = markidPkg pkgs.stdenv.hostPlatform.system;
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
            - `media_sources` (table, optional): named media directories for ```media``` blocks. Prefer the `mediaSources` option — it merges into this table automatically.
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

      naturalEarthData = mkOption {
        type = types.nullOr types.package;
        default = naturalEarthPkg pkgs.stdenv.hostPlatform.system;
        description = ''
          Natural Earth shapefile bundle used by `marki-map` to resolve
          `country/<iso>`, `admin1/<iso>/<name>`, `coastline`, and
          `neighbors/<iso>` feature references in `map` blocks.

          The package's output directory is exposed to the daemon via the
          `NATURAL_EARTH_DATA` environment variable. Set to `null` to
          disable (any map blocks referencing offline features will fail
          with a `block failed` stub on the rendered card).
        '';
      };

      mediaDir = mkOption {
        type = types.nullOr types.path;
        default = null;
        description = ''
          Single media directory — convenience shorthand for a single
          unnamed source. Prefer `mediaSources` for multiple collections.
          Exposed via `MARKID_MEDIA_DIR`; searched after any named sources.
        '';
      };

      mediaSources = mkOption {
        type = types.attrsOf types.path;
        default = {};
        description = ''
          Named media sources for the `media` block renderer. Each key
          is a source name usable as a prefix in the DSL
          (`src = "circle/de"`), and the value is a directory containing
          the media files (images and/or audio). Order matters: when no
          prefix is given, sources are searched in definition order and
          the first match wins.

          Supported file extensions:
            - Images: svg, png, webp, jpg, jpeg, gif
            - Audio: mp3, ogg, m4a, wav

          Written to `[media_sources]` in `config.toml`. Set to `{}` to
          disable — any ```media``` blocks then fall through to plain code
          rendering.
        '';
        example = literalExpression ''
          {          circle = "''${pkgs.circle-flags}/share/circle-flags-svg";
            flags = "''${hayleox-flags}/share/hayleox-flags";
          }
        '';
      };

      typstPackage = mkOption {
        type = types.nullOr types.package;
        default = null;
        description = ''
          Typst package used to render ```typst``` blocks. The binary
          path is exposed to the daemon via `MARKID_TYPST`. Set to
          `pkgs.typst` (or a custom derivation with extra fonts) to
          enable. Set to `null` (the default) to disable — any
          ```typst``` blocks then fall through to plain code rendering.

          The user controls the install: install Typst Universe packages
          like `@preview/circuiteria`, set `TYPST_FONT_PATHS` for custom
          fonts, or pin a specific version. Markid just invokes whatever
          binary is configured here.
        '';
        example = literalExpression "pkgs.typst";
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
            Environment =
              [
                "RUST_LOG=${cfg.logLevel}"
                "MARKID_CONFIG=%h/.config/markid/config.toml"
              ]
              ++ optional (cfg.naturalEarthData != null)
              "NATURAL_EARTH_DATA=${cfg.naturalEarthData}"
              ++ optional (cfg.mediaDir != null)
              "MARKID_MEDIA_DIR=${cfg.mediaDir}"
              ++ optional (cfg.typstPackage != null)
              "MARKID_TYPST=${getExe cfg.typstPackage}";
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
  };
}

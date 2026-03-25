# Dagu - workflow engine service module
# Runs the dagu server + scheduler + coordinator as a systemd service
{
  config,
  lib,
  pkgs,
  self,
  ...
}:
let
  cfg = config.services.dagu;

  # Build the YAML config file from settings
  settingsFormat = pkgs.formats.yaml {};

  # Merge explicit options into the settings attrset
  effectiveSettings =
    lib.recursiveUpdate cfg.settings (
      lib.filterAttrs (_: v: v != null) {
        host = cfg.host;
        port = cfg.port;
        tz = cfg.timezone;
      }
      // lib.optionalAttrs (cfg.auth.mode != null) {
        auth.mode = cfg.auth.mode;
      }
      // lib.optionalAttrs (cfg.dagsDir != null) {
        paths.dags_dir = cfg.dagsDir;
      }
    );

  configFile = settingsFormat.generate "dagu-config.yaml" effectiveSettings;

  # Generate DAG files from inline definitions
  dagFiles = lib.mapAttrs (
    name: dagCfg:
      pkgs.writeText "dagu-dag-${name}.yaml" dagCfg.content
  ) cfg.dags;
in
{
  options.services.dagu = {
    enable = lib.mkEnableOption "dagu workflow engine";

    package = lib.mkOption {
      type = lib.types.package;
      default = self.packages.${pkgs.stdenv.hostPlatform.system}.dagu;
      description = "The dagu package to use.";
    };

    host = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
      description = "Address to bind the web server to.";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 8080;
      description = "Port for the web server.";
    };

    timezone = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "America/New_York";
      description = "Timezone for scheduling. Defaults to system timezone.";
    };

    dataDir = lib.mkOption {
      type = lib.types.path;
      default = "/var/lib/dagu";
      description = "Directory for dagu state, data, and logs.";
    };

    dagsDir = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        Directory for DAG definition files.
        Defaults to `<dataDir>/dags` if not set.
        When `dags` are defined inline, they are symlinked into this directory.
      '';
    };

    user = lib.mkOption {
      type = lib.types.str;
      default = "dagu";
      description = "User account under which dagu runs.";
    };

    group = lib.mkOption {
      type = lib.types.str;
      default = "dagu";
      description = "Group under which dagu runs.";
    };

    auth = {
      mode = lib.mkOption {
        type = lib.types.nullOr (lib.types.enum ["none" "basic" "builtin"]);
        default = null;
        description = ''
          Authentication mode. `null` leaves it at dagu's default (`builtin`).
          - `none`: No authentication
          - `basic`: HTTP basic auth (set credentials via environmentFile)
          - `builtin`: Built-in auth with JWT tokens
        '';
      };
    };

    environmentFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = ''
        Path to an environment file loaded by systemd (EnvironmentFile=).
        Use this for secrets that should not end up in the Nix store.

        Useful variables:
        - `DAGU_AUTH_BASIC_USERNAME` / `DAGU_AUTH_BASIC_PASSWORD` (for basic auth)
        - `DAGU_AUTH_TOKEN_SECRET` (for builtin auth JWT secret)
        - `DAGU_AUTH_BUILTIN_INITIAL_ADMIN_USERNAME` / `DAGU_AUTH_BUILTIN_INITIAL_ADMIN_PASSWORD`
        - `DAGU_CERT_FILE` / `DAGU_KEY_FILE` (for TLS)
      '';
      example = "/run/secrets/dagu-env";
    };

    settings = lib.mkOption {
      type = settingsFormat.type;
      default = {};
      description = ''
        Freeform settings written to dagu's config.yaml.
        See https://dagu.readthedocs.io for all available options.
        Explicit module options (host, port, auth.mode, etc.) take precedence.
      '';
      example = lib.literalExpression ''
        {
          ui.navbar_color = "#1a1a2e";
          ui.navbar_title = "My Workflows";
          scheduler.zombie_detection_interval = "60s";
          terminal.enabled = true;
        }
      '';
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Whether to open the firewall for the dagu web server port.";
    };

    dags = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule {
        options = {
          content = lib.mkOption {
            type = lib.types.lines;
            description = "YAML content of the DAG definition.";
            example = ''
              type: graph
              schedule: "0 * * * *"
              steps:
                - id: hello
                  command: echo "hello from dagu"
            '';
          };
        };
      });
      default = {};
      description = ''
        Declarative DAG workflow definitions.
        Each key becomes a `<name>.yaml` file in the DAGs directory.
      '';
      example = lib.literalExpression ''
        {
          backup = {
            content = '''
              type: graph
              schedule: "0 2 * * *"
              steps:
                - id: backup_db
                  command: pg_dump mydb > /backup/db.sql
            ''';
          };
        }
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    users.users.${cfg.user} = lib.mkIf (cfg.user == "dagu") {
      isSystemUser = true;
      group = cfg.group;
      home = cfg.dataDir;
      description = "Dagu workflow engine user";
    };

    users.groups.${cfg.group} = lib.mkIf (cfg.group == "dagu") {};

    networking.firewall.allowedTCPPorts = lib.mkIf cfg.openFirewall [cfg.port];

    systemd.services.dagu = {
      description = "Dagu workflow engine";
      after = ["network.target"];
      wantedBy = ["multi-user.target"];

      preStart = let
        effectiveDagsDir =
          if cfg.dagsDir != null
          then cfg.dagsDir
          else "${cfg.dataDir}/dags";
      in ''
        # Ensure the DAGs directory exists
        mkdir -p "${effectiveDagsDir}"

        ${lib.concatStringsSep "\n" (lib.mapAttrsToList (
          name: dagFile: ''
            ln -sf ${dagFile} "${effectiveDagsDir}/${name}.yaml"
          ''
        ) dagFiles)}
      '';

      serviceConfig = {
        Type = "simple";
        User = cfg.user;
        Group = cfg.group;

        ExecStart = "${lib.getExe cfg.package} start-all --config=${configFile}";

        StateDirectory = "dagu";
        StateDirectoryMode = "0750";
        WorkingDirectory = cfg.dataDir;

        Environment = [
          "DAGU_HOME=${cfg.dataDir}"
          "DAGU_DATA_DIR=${cfg.dataDir}"
          "HOME=${cfg.dataDir}"
        ];

        EnvironmentFile = lib.mkIf (cfg.environmentFile != null) cfg.environmentFile;

        Restart = "on-failure";
        RestartSec = 5;

        # Hardening
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
        ReadWritePaths = [cfg.dataDir] ++ lib.optional (cfg.dagsDir != null) cfg.dagsDir;
      };
    };
  };
}

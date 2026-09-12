{ ... }: {
  home =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      inherit (lib)
        mkEnableOption
        mkOption
        mkIf
        types
        getExe
        ;
      cfg = config.services.prompt-daemon;
      yamlFormat = pkgs.formats.yaml { };

      configFile = yamlFormat.generate "prompt-daemon-config.yaml" {
        daemon = cfg.daemon;
        defaults = cfg.defaults;
        commands = cfg.commands;
      };
    in
    {
      options.services.prompt-daemon = {
        enable = mkEnableOption "prompt-daemon, a pre-computation cache daemon for shell prompt segments";

        package = mkOption {
          type = types.package;
          description = "The prompt-daemon package to use.";
        };

        daemon = mkOption {
          type = yamlFormat.type;
          default = { };
          description = ''
            Daemon-level settings (`daemon` section in config.yaml).
            See prompt-daemon's `config.example.yaml` for the full field list.
          '';
          example = {
            idle_timeout = "60s";
            log_level = "debug";
          };
        };

        defaults = mkOption {
          type = yamlFormat.type;
          default = { };
          description = ''
            Default settings inherited by all commands (`defaults` section).
            See prompt-daemon's `config.example.yaml` for the full field list.
          '';
          example = {
            shell = true;
            timeout = "5s";
          };
        };

        commands = mkOption {
          type = types.attrsOf yamlFormat.type;
          default = { };
          description = ''
            Command definitions. Each key is the command name used by prompt-client.
            Values map directly to the YAML command schema — see prompt-daemon's
            `config.example.yaml` for the full field list and examples of each
            invalidation strategy (interval, check, watch).
          '';
          example = {
            git_status = {
              run = "git status --porcelain";
              check = "git status --porcelain";
              check_interval = "500ms";
              idle_timeout = "30s";
              env = [ "CWD" ];
              exec_in_cwd = true;
            };
            git_branch = {
              run = "git branch --show-current";
              watch = [ ".git/HEAD" ];
              env = [ "CWD" ];
              exec_in_cwd = true;
            };
          };
        };
      };

      config = mkIf cfg.enable {
        # Both binaries (prompt-daemon + prompt-client) come from the same package
        home.packages = [ cfg.package ];

        # Generate config at ~/.config/prompt-daemon/config.yaml
        xdg.configFile."prompt-daemon/config.yaml".source = configFile;

        # Systemd user service
        systemd.user.services.prompt-daemon = {
          Unit = {
            Description = "prompt-daemon: pre-computation cache for shell prompt segments";
            # configFile is an immutable /nix/store path — it can never change in
            # place, only be replaced by a new generation. Restart whenever it does.
            X-Restart-Triggers = [ configFile ];
          };
          Service = {
            ExecStart = "${getExe cfg.package}";
            Restart = "on-failure";
            RestartSec = 5;
          };
          Install = {
            WantedBy = [ "default.target" ];
          };
        };
      };
    };
}

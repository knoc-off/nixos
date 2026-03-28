{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (lib) mkEnableOption mkOption mkIf types getExe;
  cfg = config.services.prompt-daemon;
  yamlFormat = pkgs.formats.yaml {};

  # Strip null values and empty lists/attrsets so the generated YAML is clean.
  # The daemon uses serde defaults for missing fields, so omission is correct.
  filterNulls = attrs:
    lib.pipe attrs [
      (lib.filterAttrs (_: v: v != null))
      (lib.mapAttrs (_: v:
        if builtins.isAttrs v
        then filterNulls v
        else if builtins.isList v
        then builtins.filter (x: x != null) v
        else v))
      (lib.filterAttrs (_: v:
        !(builtins.isAttrs v && v == {})
        && !(builtins.isList v && v == [])))
    ];

  configFile = yamlFormat.generate "prompt-daemon-config.yaml" (filterNulls {
    daemon = cfg.daemon;
    defaults = cfg.defaults;
    commands = lib.mapAttrs (_: filterNulls) cfg.commands;
  });
in {
  options.services.prompt-daemon = {
    enable = mkEnableOption "prompt-daemon, a pre-computation cache daemon for shell prompt segments";

    package = mkOption {
      type = types.package;
      description = "The prompt-daemon package to use.";
    };

    daemon = mkOption {
      type = yamlFormat.type;
      default = {};
      description = ''
        Daemon-level settings. Maps directly to the `daemon` section in config.yaml.

        Common fields:
        - `workers` (int): max concurrent command executions. Default: 4.
        - `idle_timeout` (string): global scheduler cold timeout. Default: "60s".
        - `log_level` (string): tracing filter. Default: "info".
      '';
      example = {
        workers = 2;
        idle_timeout = "60s";
        log_level = "debug";
      };
    };

    defaults = mkOption {
      type = yamlFormat.type;
      default = {};
      description = ''
        Default settings inherited by all commands. Maps to the `defaults` section.

        Common fields:
        - `shell` (bool): run commands via /bin/sh -c. Default: false.
        - `timeout` (string): command execution timeout. Default: "10s".
        - `stale.on_empty`, `stale.on_expired`, etc.: placeholder text.
      '';
      example = {
        shell = true;
        timeout = "5s";
      };
    };

    commands = mkOption {
      type = types.attrsOf yamlFormat.type;
      default = {};
      description = ''
        Command definitions. Each key is the command name used by prompt-client.
        Values map directly to the YAML command schema.

        Common fields:
        - `run` (string, required): the command to execute.
        - `shell` (bool): override defaults.shell.
        - `env` (list of string): env vars for cache key derivation. "CWD" is magic.
        - `exec_in_cwd` (bool): execute in the client's working directory.
        - `interval` (string): re-execution interval (e.g. "2s", "120s").
        - `check` (string): cheap sensor command; re-run if output changes.
        - `check_interval` (string): how often to run check. Default: "1s".
        - `watch` (list of string): file paths to watch via inotify.
        - `idle_timeout` (string): per-command override for scheduler cold timeout.
        - `max_age` (string): cached value expiry.
        - `timeout` (string): per-command execution timeout.
      '';
      example = {
        git_status = {
          run = "git status --porcelain";
          check = "git status --porcelain";
          check_interval = "500ms";
          idle_timeout = "30s";
          env = ["CWD"];
          exec_in_cwd = true;
        };
        git_branch = {
          run = "git branch --show-current";
          watch = [".git/HEAD"];
          env = ["CWD"];
          exec_in_cwd = true;
        };
      };
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.commands != {};
        message = "services.prompt-daemon: at least one command must be configured.";
      }
    ];

    # Both binaries (prompt-daemon + prompt-client) come from the same package
    home.packages = [cfg.package];

    # Generate config at ~/.config/prompt-daemon/config.yaml
    xdg.configFile."prompt-daemon/config.yaml".source = configFile;

    # Systemd user service
    systemd.user.services.prompt-daemon = {
      Unit = {
        Description = "prompt-daemon: pre-computation cache for shell prompt segments";
      };
      Service = {
        ExecStart = "${getExe cfg.package}";
        Restart = "on-failure";
        RestartSec = 5;
      };
      Install = {
        WantedBy = ["default.target"];
      };
    };
  };
}

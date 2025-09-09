{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.programs.hyprkan;

  # Convert a rule attrset to JSON-compatible format
  ruleToJson = rule: 
    lib.filterAttrs (n: v: v != null) {
      class = rule.class;
      title = rule.title;
      layer = rule.layer;
      cmd = rule.cmd;
      fake_key = rule.fakeKey;
      set_mouse = rule.setMouse;
    };

  configFile = pkgs.writeText "hyprkan-config.json" 
    (builtins.toJSON (map ruleToJson cfg.rules));

  ruleType = types.submodule {
    options = {
      class = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = ''
          Window class to match. Supports regex patterns.
          Use "*" to match any class, or null/false to ignore class matching.
        '';
        example = "^kitty$";
      };

      title = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = ''
          Window title to match. Supports regex patterns.
          Use "*" to match any title, or null/false to ignore title matching.
        '';
        example = "^vim$";
      };

      layer = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = ''
          Kanata layer to switch to when this rule matches.
          Set to null or false to disable layer switching for matching windows.
        '';
        example = "vim_layer";
      };

      cmd = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = ''
          Shell command to execute when this rule matches.
        '';
        example = "notify-send 'Switched to vim'";
      };

      fakeKey = mkOption {
        type = types.nullOr (types.listOf types.str);
        default = null;
        description = ''
          Kanata virtual key to trigger when this rule matches.
          Format: ["key_name", "action"]
        '';
        example = ["esc" "tap"];
      };

      setMouse = mkOption {
        type = types.nullOr (types.listOf types.int);
        default = null;
        description = ''
          Mouse position to set when this rule matches.
          Format: [x, y]
        '';
        example = [300 400];
      };
    };
  };

in {
  options.programs.hyprkan = {
    enable = mkEnableOption "hyprkan, an app-aware Kanata layer switcher";

    package = mkOption {
      type = types.package;
      default = pkgs.hyprkan;
      description = "The hyprkan package to use.";
    };

    configFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = ''
        Path to the hyprkan configuration file.
        If null, a configuration file will be generated from the rules option.
      '';
    };

    rules = mkOption {
      type = types.listOf ruleType;
      default = [];
      description = ''
        List of window matching rules for hyprkan.
        Rules are processed top to bottom, with the first matching rule being used.
      '';
      example = [
        {
          class = "^kitty$";
          title = "^vim$";
          layer = "vim_layer";
        }
        {
          class = "chrome";
          title = "YouTube";
          layer = "media";
        }
        {
          class = "*";
          title = "*";
          layer = "base_layer";
        }
      ];
    };

    service = {
      enable = mkEnableOption "hyprkan systemd user service";

      extraArgs = mkOption {
        type = types.listOf types.str;
        default = [];
        description = "Extra arguments to pass to hyprkan.";
        example = ["--verbose" "--debug"];
      };
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.configFile != null || cfg.rules != [];
        message = "programs.hyprkan: either configFile or rules must be specified";
      }
    ];

    home.packages = [ cfg.package ];

    # Generate or use custom config file
    xdg.configFile."kanata/apps.json" = {
      source = if cfg.configFile != null then cfg.configFile else configFile;
    };

    # Systemd user service
    systemd.user.services.hyprkan = mkIf cfg.service.enable {
      Unit = {
        Description = "Kanata Layer Switcher";
        After = [ "graphical-session.target" ];
        PartOf = [ "graphical-session.target" ];
      };

      Service = {
        ExecStart = "${cfg.package}/bin/hyprkan" + 
          (if cfg.configFile != null 
           then " --config ${cfg.configFile}"
           else "") +
          (if cfg.service.extraArgs != []
           then " " + (concatStringsSep " " cfg.service.extraArgs)
           else "");
        Restart = "on-failure";
        RestartSec = 5;
        Type = "simple";
      };

      Install = {
        WantedBy = [ "graphical-session.target" ];
      };
    };
  };
}
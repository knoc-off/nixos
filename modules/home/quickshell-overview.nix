{
  config,
  lib,
  pkgs,
  self,
  ...
}: let
  cfg = config.programs.quickshell-overview;
  system = pkgs.stdenv.hostPlatform.system;
  qs = lib.getExe cfg.quickshellPackage;
  jsonFormat = pkgs.formats.json {};
  hyprlandEnabled = config.wayland.windowManager.hyprland.enable;
in {
  options.programs.quickshell-overview = {
    enable = lib.mkEnableOption "quickshell-overview, a Hyprland workspace overview using Quickshell";

    package = lib.mkOption {
      type = lib.types.package;
      default = self.packages.${system}.quickshell-overview;
      description = "The quickshell-overview QML files package.";
    };

    quickshellPackage = lib.mkOption {
      type = lib.types.package;
      default = pkgs.quickshell;
      description = "The Quickshell package providing the qs binary.";
    };

    settings = lib.mkOption {
      type = jsonFormat.type;
      default = {};
      description = ''
        User config overrides written to config.json.
        See config.example.json in the source for available options.
      '';
      example = lib.literalExpression ''
        {
          overview = {
            rows = 2;
            columns = 5;
            scale = 0.16;
          };
        }
      '';
    };

    keybind = lib.mkOption {
      type = lib.types.str;
      default = "SUPER, TAB";
      description = "Hyprland bind prefix used to toggle the overview.";
    };
  };

  config = lib.mkIf cfg.enable {
    # Deploy QML files as individual symlinks so a runtime config.json can
    # coexist in the same directory without being managed by home-manager.
    xdg.configFile =
      {
        "quickshell/overview" = {
          source = "${cfg.package}/share/quickshell-overview";
          recursive = true;
        };
      }
      // lib.optionalAttrs (cfg.settings != {}) {
        "quickshell/overview/config.json".source =
          jsonFormat.generate "quickshell-overview-config.json" cfg.settings;
      };

    systemd.user.services.quickshell-overview = {
      Unit = {
        Description = "Quickshell workspace overview for Hyprland";
        After = ["graphical-session.target"];
        PartOf = ["graphical-session.target"];
        # Only meaningful inside a Hyprland session
        ConditionEnvironment = "HYPRLAND_INSTANCE_SIGNATURE";
      };
      Service = {
        ExecStart = "${qs} -c overview";
        Restart = "on-failure";
        RestartSec = 2;
      };
      Install.WantedBy = ["graphical-session.target"];
    };

    wayland.windowManager.hyprland.settings = lib.mkIf hyprlandEnabled {
      bind = [
        "${cfg.keybind}, exec, ${qs} ipc -c overview call overview toggle"
      ];
    };
  };
}

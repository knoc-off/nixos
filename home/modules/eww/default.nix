{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  pamixer = "${pkgs.pamixer}/bin/pamixer";
  pactl = "${pkgs.pulseaudio}/bin/pactl";

  cfg = config.programs.eww;
in {
  #meta.maintainers = [ hm.maintainers.mainrs ];

  options.programs.eww = {
    enable = mkEnableOption "eww";

    config = mkOption {
      type = types.attrs;
      default = {
        bar = {
          enable = true;
          side = "top";
        };
        example = ''
          {
            bar = {
              enable = false;
              side = "bottom";
            };
          }
        '';
        description = ''
          The eww configuration.
        '';
      };
    };

    package = mkOption {
      type = types.package;
      default = pkgs.eww; # Check if wayland is available?
      defaultText = literalExpression "pkgs.eww";
      example = literalExpression "pkgs.eww-wayland";
      description = ''
        The eww package to install.
      '';
    };
  };

  config = mkIf cfg.enable {
    home.packages = [cfg.package];
    #xdg.configFile."eww".source = cfg.configDir;

    xdg.configFile = let
      dir = "eww";
      scripts = "${dir}/scripts";
    in {
      "${dir}/eww.yuck" = {
        text =
          ''
            (defvar user_name "${config.home.username}")
          ''
          + (
            if cfg.config.bar.enable
            then ''(import ./bar.yuck)''
            else ''''
          );
      };

      "${dir}/eww.scss" = {
        text = ''
        '';
      };

      "${dir}/bar.yuck" = {
        enable = cfg.config.bar.enable;
        text = ''
          (defwindow bar
              :monitor 0
              :exclusive true
              :stacking "fg"
              :namespace "eww_bar"
              :geometry (geometry :width "100%"
                                  :height "1%"
                                  :anchor "top center")(hbar))
        '';
      };
    };
  };
}

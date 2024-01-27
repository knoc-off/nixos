{ config, lib, pkgs, ... }:

with lib;

let

  cfg = config.programs.eww;

in
{
  meta.maintainers = [ hm.maintainers.mainrs ];

  options.programs.eww = {
    enable = mkEnableOption "eww";


    config = mkOption {
      type = types.attrsOf types.any;
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
    home.packages = [ cfg.package ];
    #xdg.configFile."eww".source = cfg.configDir;

    xdg.configFile =
      let
        dir = "eww2";
      in
      {
        "${dir}/eww.yuck" = {
          text = ''

          ''
          #(if cfg.config.bar.enable then import ./bar.yuck else '' '')
          ;
        };
        "${dir}/bar.yuck" = {
          enable = cfg.config.bar.enable;
          text = ''

          '';
        };
        "${dir}/eww.scss" = {
          text = ''
            @import "eww";

            @include eww;
          '';
        };

      };
  };
}

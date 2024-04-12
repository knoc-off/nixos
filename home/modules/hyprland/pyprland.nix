{ pkgs, config, lib, ... }:
let
  cfg = config.pyprland;
in
with lib;
{
  options = {
    pyprland = {
      enable = mkEnableOption "pyperland";

      package = mkOption {
        default = pkgs.pyprland;
        type = types.package;
        description = "The pyprland package to use";
      };

      extraPlugins = mkOption {
        default = [];
        type = with types; listOf str;
        description = "Additional plugins to enable";
      };

      config = mkOption {
        default = {};
        type = with types; attrsOf (oneOf [ str int bool ]);
        description = "Additional pyprland configuration options";
      };

      scratchpads = mkOption {
        default = {};
        type = with types; attrsOf (submodule {
          options = {
            animation = mkOption {
              type = str;
              description = "Animation type for the scratchpad";
            };
            command = mkOption {
              type = str;
              description = "Command to execute for the scratchpad";
            };
            class = mkOption {
              type = str;
              description = "Window class for the scratchpad";
            };
            lazy = mkOption {
              type = bool;
              default = false;
              description = "Whether to lazily spawn the scratchpad";
            };
            size = mkOption {
              type = str;
              description = "Size of the scratchpad window";
            };
            unfocus = mkOption {
              type = str;
              default = "hide";
              description = "Behavior when the scratchpad loses focus";
            };
          };
        });
        description = "Scratchpad configurations";
      };
    };
  };

  config = mkIf cfg.enable {
    home.packages = [
      cfg.package
    ];

    home.file."pyprland" = {
      target = ".config/hypr/pyprland.toml";
      source = pkgs.writers.writeTOML "pyprland.toml" (recursiveUpdate {
        pyprland = {
          plugins = cfg.extraPlugins ++ (optional (cfg.scratchpads != {}) "scratchpads");
        };
      } (recursiveUpdate cfg.config {
        scratchpads = mapAttrs (name: value: removeAttrs value ["_module"]) cfg.scratchpads;
      }));
    };
  };
}

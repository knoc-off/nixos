{ pkgs, config, lib, ...}:
let
  cfg = config.hyprland.pyperland;
in
with lib;
{
  options = {
    hyprland.pyperland = {
      enable = {
        default = false;
        type = with types; bool;
      };
      extraPlugins = {
        type = with types; listOf str;
        description = ''
          plugins to enable
        '';

      };

      plugins = {
        scratchpads = {
          enable = {
            default = false;
            type = with types; bool;
            #scratchpads = {
            #  default = {};
              #type = with types; listOf;
#
            #};
          };
        };
      };
    };
  };

  config = {
    home.packages = [
      pkgs.pyprland
    ];

    home.file."pyprland" = {
      target = ".config/hypr/pyprland.toml";
      source = pkgs.writers.writeTOML "pyprland.toml" {
        pyprland = {
          plugins = [
            "scratchpads"
            "expose"
            #"shift_monitors"
            #"workspaces_follow_focus"
          ];
        };

        scratchpads = {
          stb-logs = {
            animation = "fromTop";
            command = "kitty --class kitty-stb-logs stbLog";
            class = "kitty-stb-logs";
            lazy = true;
            size = "75% 40%";
          };

          term = {
            animation = "fromTop";
            command = "kitty --class kitty-dropterm";
            class = "kitty-dropterm";
            unfocus = "hide";
            size = "75% 60%";
          };

          file = {
            animation = "fromBottom";
            command = "nautilus";
            class = "filemanager";
            size = "75% 60%";
            unfocus = "hide";
          };

          volume = {
            animation = "fromRight";
            command = "pavucontrol";
            class = "pavucontrol";
            lazy = true;
            size = "40% 90%";
            unfocus = "hide";

          };
        };
      };
    };
  };
}

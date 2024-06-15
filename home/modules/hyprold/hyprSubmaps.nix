{ config, lib, ... }:

with lib;

let
  cfg = config.wayland.windowManager.hyprland;

  submapModule = { name, ... }: {
    options = {
      name = mkOption {
        type = types.str;
        default = name;
        description = "Name of the submap.";
      };

      keybinds = mkOption {
        type = types.listOf types.str;
        default = [];
        description = "Keybinds for the submap.";
      };
    };
  };

  submapsConfig = concatStringsSep "\n" (mapAttrsToList (name: submap:
    ''
      submap = ${name}
      ${concatStringsSep "\n" submap.keybinds}
      bind = , escape, submap, reset
    ''
  ) cfg.submaps);
in {
  options.wayland.windowManager.hyprland = {
    submaps = mkOption {
      type = types.attrsOf (types.submodule submapModule);
      default = {};
      description = "Submaps configuration for Hyprland window manager.";
    };
  };

  config = {
    wayland.windowManager.hyprland.extraConfig = mkAfter submapsConfig;
  };
}


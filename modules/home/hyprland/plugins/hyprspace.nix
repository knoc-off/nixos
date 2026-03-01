{ inputs, pkgs, ... }:
let
  system = pkgs.stdenv.hostPlatform.system;
in {
  wayland.windowManager.hyprland = {
    plugins = [ inputs.Hyprspace.packages.${system}.Hyprspace ];
    settings.bind = [
      "SUPER, grave, overview:toggle"
    ];
  };
}

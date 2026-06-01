{
  inputs,
  pkgs,
  ...
}: let
  system = pkgs.stdenv.hostPlatform.system;
in {
  wayland.windowManager.hyprland.plugins = [
    inputs.hyprland-plugins.packages.${system}.xtra-dispatchers
  ];
}

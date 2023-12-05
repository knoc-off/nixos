{ lib, pkgs, inputs, ... }:
{
  imports = [
    inputs.hyprland.homeManagerModules.default
    { wayland.windowManager.hyprland.enable = true; }
  ];
  wayland.windowManager.hyprland.extraConfig = ''
    $mod = SUPER
  '';
  wayland.windowManager.hyprland = {
    enable = true;
    plugins = [
      inputs.hyprland-plugins.packages.${pkgs.system}.hyprbars
    ];
  };


}

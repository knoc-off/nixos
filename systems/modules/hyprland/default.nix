{ inputs, config, lib, pkgs, ... }:
let

in
{

  programs.hyprland = {
    enable = true;
    package = inputs.hyprland.packages.${pkgs.system}.hyprland;
  };



  #wayland.windowManager.hyprland.settings = {
  #  enable = true;
  #  package = inputs.hyprland.packages.${pkgs.system}.hyprland;
  #};

  nix.settings = {
    substituters = [ "https://hyprland.cachix.org" ];
    trusted-public-keys = [ "hyprland.cachix.org-1:a7pgxzMz7+chwVL3/pzj6jIBMioiJM7ypFP8PwtkuGc=" ];
  };


}

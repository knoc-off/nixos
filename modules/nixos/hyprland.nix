{ inputs, pkgs, ... }:
let
  system = pkgs.stdenv.hostPlatform.system;
in {
  programs.hyprland = {
    enable = true;
    package = inputs.hyprnix.packages.${system}.hyprland;
    portalPackage = inputs.hyprnix.packages.${system}.xdg-desktop-portal-hyprland;
    withUWSM = true;
  };

  security.polkit.enable = true;

  environment.systemPackages = with pkgs; [
    wl-clipboard
    xdg-utils
  ];

  xdg.portal = {
    enable = true;
    extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
    config.common.default = [ "hyprland" "gtk" ];
  };

  environment.sessionVariables.NIXOS_OZONE_WL = "1";
}

{ inputs, config, lib, pkgs, self, ... }:

let

in {
  imports = [ self.nixosModules.desktop.totem ];

  # Enable backlight control
  programs.light.enable = true;

  # Allow X compositor
  # services.xserver.displayManager.startx.enable = lib.mkDefault true;

  # Enable Hyprland
  programs.hyprland = {
    enable = true;
    xwayland.enable = true;
  };

  # XDG portal configuration
  xdg.portal = {
    enable = lib.mkDefault true;
    extraPortals = lib.mkDefault [
      pkgs.xdg-desktop-portal-hyprland
      pkgs.xdg-desktop-portal-gtk
      pkgs.xdg-desktop-portal-kde
    ];

    config.common.default = "hyprland";
  };

  # System-wide packages
  environment.systemPackages = with pkgs; [ wl-clipboard xdg-utils ];

  # Enable polkit
  security.polkit.enable = lib.mkDefault true;

  # hint Wayland for Electron apps
  environment.sessionVariables.NIXOS_OZONE_WL = lib.mkDefault "1";

}

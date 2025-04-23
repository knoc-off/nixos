{ inputs, config, lib, pkgs, self, ... }:

let
  tuigreet = "${pkgs.greetd.tuigreet}/bin/tuigreet";
  hyprland = "${pkgs.hyprland}/bin/Hyprland";

in {
  #imports = [ self.nixosModules.desktop.totem ];

  # Enable greetd for login
  services.greetd = {
    enable = lib.mkDefault true;
    settings = lib.mkDefault {
      default_session.command = "${tuigreet} --remember --cmd ${hyprland}";
    };
  };

  # Enable backlight control
  programs.light.enable = lib.mkDefault true;

  # Allow X compositor
  services.xserver.displayManager.startx.enable = lib.mkDefault true;

  # Enable Hyprland
  programs.hyprland = {
    enable = lib.mkDefault true;
    package = lib.mkDefault inputs.hyprland.packages.${pkgs.system}.hyprland;
    xwayland.enable = lib.mkDefault true;
  };

  # XDG portal configuration
  xdg.portal = {
    enable = lib.mkDefault true;
    extraPortals = lib.mkDefault [
      pkgs.xdg-desktop-portal-gtk
      pkgs.xdg-desktop-portal-hyprland
    ];
  };

  # System-wide packages
  environment.systemPackages = lib.mkDefault (with pkgs; [
    wl-clipboard
    xdg-utils

    vaapiVdpau
    libvdpau-va-gl

  ]);

  # Enable polkit
  security.polkit.enable = lib.mkDefault true;

  # Enable Wayland for Electron apps
  environment.sessionVariables.NIXOS_OZONE_WL = lib.mkDefault "1";

}

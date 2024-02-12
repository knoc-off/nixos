{ inputs, config, pkgs, ... }:
{

  services.greetd.enable = true;

  # For greetd, we need a shell script into path, which lets us start qtile.service (after importing the environment of the login shell).
  services.greetd.settings.default_session.command = "${pkgs.greetd.tuigreet}/bin/tuigreet --remember --cmd ${pkgs.writeScript "Hyprland_start" ''
    #! ${pkgs.bash}/bin/bash

    # Do stuff

    # Hyprland
    ${pkgs.hyprland}/bin/Hyprland
  ''}";

  # Backlight control. TODO: link to the package instead of installing it?
  programs.light.enable = true;

  # allow x compositor
  services.xserver = {
    displayManager.startx.enable = true;
  };

  # hyprland.
  programs.hyprland = {
    enable = true;
    package = inputs.hyprland.packages.${pkgs.system}.hyprland;
    xwayland.enable = true;
  };

  # portals
  xdg.portal = {
    enable = true;
    extraPortals = [
      pkgs.xdg-desktop-portal-gnome
      pkgs.xdg-desktop-portal-gtk
    ];
  };

  environment.systemPackages = with pkgs; [
    gnome.adwaita-icon-theme
    gnome.nautilus
    gnome.gnome-calendar
    gnome.gnome-boxes
    gnome.gnome-system-monitor
    gnome.gnome-control-center
    gnome.gnome-weather
    gnome.gnome-calculator
    gnome.gnome-software # for flatpak
    swaylock
    swayidle

    # super useful
    wl-clipboard

    # lets see if xdg fixes things
    xdg-utils

  ];

  security.pam.services.swaylock = { };
  # I believe this is redundant, but I'm not sure
  security.pam.services.swaylock.fprintAuth = config.services.fprintd.enable;

  # this should be enabled by default, with hyprland
  security = {
    polkit.enable = true;
  };

  # TODO: Document this.
  services = {
    gvfs.enable = true;
    devmon.enable = true;
    udisks2.enable = true;
    upower.enable = true;
    accounts-daemon.enable = true;
    gnome = {
      evolution-data-server.enable = true;
      glib-networking.enable = true;
      gnome-keyring.enable = true;
      gnome-online-accounts.enable = true;
    };
  };

  environment.sessionVariables.NIXOS_OZONE_WL = "1"; # electron apps use wayland

}

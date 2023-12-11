{ inputs, pkgs, ... }:
{


  services.greetd.enable = true;

  # For greetd, we need a shell script into path, which lets us start qtile.service (after importing the environment of the login shell).
  services.greetd.settings.default_session.command = "${pkgs.greetd.tuigreet}/bin/tuigreet --remember --cmd ${pkgs.writeScript "startqtile" ''
    #! ${pkgs.bash}/bin/bash

    # first import environment variables from the login manager
    # export XDG_DATA_DIRS=/run/current-system/sw/share/gsettings-schemas:$XDG_DATA_DIRS
    # systemctl --user unset-environment DISPLAY WAYLAND_DISPLAY

    #zsh --login -c "systemctl --user import-environment XDG_DATA_DIRS PATH"

    hypr
  ''}";



  services.xserver = {
    displayManager.startx.enable = true;
  };

  programs.hyprland = {
    enable = true;
    package = inputs.hyprland.packages.${pkgs.system}.hyprland;
    xwayland.enable = true;
  };

  xdg.portal = {
    enable = true;
    extraPortals = [ pkgs.xdg-desktop-portal-gnome ];
  };

  security = {
    polkit.enable = true;
  };

  security.pam.services.swaylock = { };
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
  ];





  systemd = {
    user.services.polkit-gnome-authentication-agent-1 = {
      description = "polkit-gnome-authentication-agent-1";
      wantedBy = [ "graphical-session.target" ];
      wants = [ "graphical-session.target" ];
      after = [ "graphical-session.target" ];
      serviceConfig = {
        Type = "simple";
        ExecStart = "${pkgs.polkit_gnome}/libexec/polkit-gnome-authentication-agent-1";
        Restart = "on-failure";
        RestartSec = 1;
        TimeoutStopSec = 10;
      };
    };
  };

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

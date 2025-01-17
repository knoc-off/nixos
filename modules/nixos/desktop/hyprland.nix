{ inputs, config, pkgs, ... }:

let
  tuigreet = "${pkgs.greetd.tuigreet}/bin/tuigreet";
  hyprland = "${pkgs.hyprland}/bin/Hyprland";

in {
  # Enable greetd for login
  services.greetd = {
    enable = true;
    settings = {
      default_session.command = "${tuigreet} --remember --cmd ${hyprland}";
    };
  };

  # Enable backlight control
  programs.light.enable = true;

  # Allow X compositor
  services.xserver.displayManager.startx.enable = true;

  # Enable Hyprland
  programs.hyprland = {
    enable = true;
    package = inputs.hyprland.packages.${pkgs.system}.hyprland;
    xwayland.enable = true;
  };

  # XDG portal configuration
  xdg.portal = {
    enable = true;
    extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
  };

  # System-wide packages
  environment.systemPackages = with pkgs; [ wl-clipboard xdg-utils ];

  # Enable polkit
  security.polkit.enable = true;


  # Enable Wayland for Electron apps
  environment.sessionVariables.NIXOS_OZONE_WL = "1";

}

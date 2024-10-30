{ inputs, config, pkgs, ... }: {
  # Enable greetd for login
  services.greetd = {
    enable = true;
    settings.default_session.command =
    "${pkgs.greetd.tuigreet}/bin/tuigreet --remember --cmd ${pkgs.hyprland}";
    #${
    #    pkgs.writeScriptBin "Hyprland_start" ''
    #      ${pkgs.hyprland}/bin/Hyprland
    #    ''
    #  }";
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
  environment.systemPackages = with pkgs; [
    wl-clipboard
    xdg-utils
  ];

  # Enable polkit
  security.polkit.enable = true;

  # Enable necessary services
  services = {
    gvfs.enable = true;
    devmon.enable = true;
    udisks2.enable = true;
    upower.enable = true;
    accounts-daemon.enable = true;
  };

  # Enable Wayland for Electron apps
  environment.sessionVariables.NIXOS_OZONE_WL = "1";
}

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

  # Fix hyprland-share-picker crash: the picker (Qt6 from hyprnix) segfaults when
  # it loads the session's Kvantum style plugin due to Qt version mismatch
  # (nixpkgs Qt 6.10.1 vs hyprnix Qt 6.10.2). Use hyprqt6engine built against
  # hyprnix's Qt so the platform theme plugin is ABI-compatible with the picker.
  systemd.user.services.xdg-desktop-portal-hyprland.serviceConfig.Environment = let
    hyprqt6engine = inputs.hyprqt6engine.packages.${system}.default;
  in [
    "QT_QPA_PLATFORMTHEME=hyprqt6engine"
    "QT_STYLE_OVERRIDE="
    "QT_PLUGIN_PATH=${hyprqt6engine}/lib/qt-6/plugins"
  ];
}

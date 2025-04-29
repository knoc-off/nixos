{
  windowManager.hyprland = import ./desktop/hyprland.nix;
  windowManager.gnome = import ./desktop/gnome.nix;
  desktop.totem = import ./desktop/media/totem.nix;

  services.axum-webserver = import ./services/axum-webserver.nix;

  home = import ./home.nix;


}

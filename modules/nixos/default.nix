{
  windowManager.hyprland = import ./desktop/hyprland.nix;
  windowManager.gnome = import ./desktop/gnome.nix;
  desktop.totem = import ./desktop/media/totem.nix;

  services.axum-webserver = import ./services/axum-webserver.nix;
  services.logiops = import ./services/logiops.nix;

  home = import ./home.nix;

  nix = import ./nix.nix;


}

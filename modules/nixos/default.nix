{
  windowManager.hyprland = import ./desktop/hyprland.nix;
  windowManager.gnome = import ./desktop/gnome.nix;
  desktop.noctalia = import ./desktop/noctalia.nix;
  desktop.totem = import ./desktop/media/totem.nix;

  audio.pipewire = import ./audio/pipewire.nix;

  minecraft.server-suite = import ./minecraft;

  services.axum-webserver = import ./services/axum-webserver.nix;
  services.logiops = import ./services/logiops.nix;

  home = import ./home.nix;

  nix = import ./nix.nix;

  misc = import ./misc.nix;
}

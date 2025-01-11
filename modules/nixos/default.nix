{
  knoff = import ./knoff.nix;
  windowManager.hyprland = import ./desktop/hyprland.nix;
  windowManager.gnome = import ./desktop/gnome.nix;
  desktop.totem = import ./desktop/media/totem.nix;
}

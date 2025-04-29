{ self, ... }:
{
  system.nixos.label = "fixed_hyprland______________________________________________________________________________" + "REV_" + toString (self.shortRev or self.dirtyShortRev or self.lastModified or "unknown") + "___________________________________________________________________________________wireguard";
}

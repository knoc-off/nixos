{ self, ... }:
{
  system.nixos.label = "hyprland_simplified._and_system_update______________________________________________________" + "REV_" + toString (self.shortRev or self.dirtyShortRev or self.lastModified or "unknown") + "_____________________________________________________________________________big_restructure";
}

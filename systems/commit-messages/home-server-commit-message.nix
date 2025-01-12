{ self, ... }:
{
  system.nixos.label = "hypreland_popup_windows_size________________________________________________________________" + "REV_" + toString (self.shortRev or self.dirtyShortRev or self.lastModified or "unknown") + "_____________________________________________________________________________big_restructure";
}

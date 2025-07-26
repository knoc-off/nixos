{ self, ... }:
{
  system.nixos.label = "hyprland____________________________________________________________________________________" + "REV_" + toString (self.shortRev or self.dirtyShortRev or self.lastModified or "unknown") + "__________________________________________________quick_changes_to_make_things_more_bareable";
}

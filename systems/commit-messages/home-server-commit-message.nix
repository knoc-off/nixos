{ self, ... }:
{
  system.nixos.label = "switch_to_ghostty" + "REV_" + toString (self.shortRev or self.dirtyShortRev or self.lastModified or "unknown") + "big_restructure";
}

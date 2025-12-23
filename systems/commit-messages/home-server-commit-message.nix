{ self, ... }:
{
  system.nixos.label = "update" + "REV_" + toString (self.shortRev or self.dirtyShortRev or self.lastModified or "unknown") + "big_restructure";
}

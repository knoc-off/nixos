{ self, ... }:
{
  system.nixos.label = "backup" + "REV_" + toString (self.shortRev or self.dirtyShortRev or self.lastModified or "unknown") + "big_restructure";
}

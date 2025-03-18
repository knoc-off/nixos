{ self, ... }:
{
  system.nixos.label = "new_packages________________________________________________________________________________" + "REV_" + toString (self.shortRev or self.dirtyShortRev or self.lastModified or "unknown") + "_____________________________________________________________________________big_restructure";
}

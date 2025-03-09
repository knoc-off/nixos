{ self, ... }:
{
  system.nixos.label = "works_quite_well____________________________________________________________________________" + "REV_" + toString (self.shortRev or self.dirtyShortRev or self.lastModified or "unknown") + "_____________________________________________________________________________________changes";
}

{ self, ... }:
{
  system.nixos.label = "logiops_overhaul____________________________________________________________________________" + "REV_" + toString (self.shortRev or self.dirtyShortRev or self.lastModified or "unknown") + "_____________________________________________________________________________big_restructure";
}

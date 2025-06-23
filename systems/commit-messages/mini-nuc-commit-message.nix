{ self, ... }:
{
  system.nixos.label = "removed_stuff_______________________________________________________________________________" + "REV_" + toString (self.shortRev or self.dirtyShortRev or self.lastModified or "unknown") + "_________________________________________________________________________________nuci5_added";
}

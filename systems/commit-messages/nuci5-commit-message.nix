{ self, ... }:
{
  system.nixos.label = "nuci5_added_________________________________________________________________________________" + "REV_" + toString (self.shortRev or self.dirtyShortRev or self.lastModified or "unknown") + "_________________________________________________________________________________nuci5_added";
}

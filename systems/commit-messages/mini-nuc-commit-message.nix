{ self, ... }:
{
  system.nixos.label = "fixes_______________________________________________________________________________________" + "REV_" + toString (self.shortRev or self.dirtyShortRev or self.lastModified or "unknown") + "_________________________________________________________________________________nuci5_added";
}

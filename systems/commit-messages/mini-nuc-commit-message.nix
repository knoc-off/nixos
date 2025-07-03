{ self, ... }:
{
  system.nixos.label = "one_last_fix-_hopefully.____________________________________________________________________" + "REV_" + toString (self.shortRev or self.dirtyShortRev or self.lastModified or "unknown") + "_________________________________________________________________________________nuci5_added";
}

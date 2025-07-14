{ self, ... }:
{
  system.nixos.label = "cli-garbage_________________________________________________________________________________" + "REV_" + toString (self.shortRev or self.dirtyShortRev or self.lastModified or "unknown") + "_________________________________________________________________________________nuci5_added";
}

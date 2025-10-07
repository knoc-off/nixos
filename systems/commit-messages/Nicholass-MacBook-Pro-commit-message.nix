{ self, ... }:
{
  system.nixos.label = "working_____________________________________________________________________________________" + "REV_" + toString (self.shortRev or self.dirtyShortRev or self.lastModified or "unknown") + "_________________________________________________________________________________quick_fixes";
}

{ self, ... }:
{
  system.nixos.label = "Pre-workspace_refactor______________________________________________________________________" + "REV_" + toString (self.shortRev or self.dirtyShortRev or self.lastModified or "unknown") + "_______________________________________________________________________________________theme";
}

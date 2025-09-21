{ self, ... }:
{
  system.nixos.label = "idk_________________________________________________________________________________________" + "REV_" + toString (self.shortRev or self.dirtyShortRev or self.lastModified or "unknown") + "_________________________________________________________________________________________wip";
}

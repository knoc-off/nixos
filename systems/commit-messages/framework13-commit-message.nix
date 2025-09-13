{ self, ... }:
{
  system.nixos.label = "wip_________________________________________________________________________________________" + "REV_" + toString (self.shortRev or self.dirtyShortRev or self.lastModified or "unknown") + "_________________________________________________________________________________________wip";
}

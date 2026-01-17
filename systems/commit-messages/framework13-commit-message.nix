{ self, ... }:
{
  system.nixos.label = "kanata_improvements" + "REV_" + toString (self.shortRev or self.dirtyShortRev or self.lastModified or "unknown") + "update";
}

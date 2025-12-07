{ self, ... }:
{
  system.nixos.label = "cleanup" + "REV_" + toString (self.shortRev or self.dirtyShortRev or self.lastModified or "unknown") + "Updated_to_25.05";
}

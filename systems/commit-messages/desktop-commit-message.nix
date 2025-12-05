{ self, ... }:
{
  system.nixos.label = "backup" + "REV_" + toString (self.shortRev or self.dirtyShortRev or self.lastModified or "unknown") + "Updated_to_25.05";
}

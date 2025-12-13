{ self, ... }:
{
  system.nixos.label = "runtime_dep" + "REV_" + toString (self.shortRev or self.dirtyShortRev or self.lastModified or "unknown") + "Updated_to_25.05";
}

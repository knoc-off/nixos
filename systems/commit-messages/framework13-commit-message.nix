{ self, ... }:
{
  system.nixos.label = "fully_functional_site_______________________________________________________________________" + "REV_" + toString (self.shortRev or self.dirtyShortRev or self.lastModified or "unknown") + "_______________________________________________________________________fully_functional_site";
}

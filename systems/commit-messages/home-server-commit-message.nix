{ self, ... }:
{
  system.nixos.label = "almost_functional_color_conversions_________________________________________________________" + "REV_" + toString (self.shortRev or self.dirtyShortRev or self.lastModified or "unknown") + "_____________________________________________________________________________big_restructure";
}

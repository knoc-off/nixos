{ self, ... }:
{
  system.nixos.label = "website_overhaul_on_axum____________________________________________________________________" + "REV_" + toString (self.shortRev or self.dirtyShortRev or self.lastModified or "unknown") + "_____________________________________________________________________________big_restructure";
}

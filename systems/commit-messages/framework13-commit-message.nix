{ self, ... }:
{
  system.nixos.label = "website_wip_________________________________________________________________________________" + "REV_" + toString (self.shortRev or self.dirtyShortRev or self.lastModified or "unknown") + "_________________________________________________________________________________website_wip";
}

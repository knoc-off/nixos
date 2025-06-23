{ self, ... }:
{
  system.nixos.label = "removed_stuff_______________________________________________________________________________" + "REV_" + toString (self.shortRev or self.dirtyShortRev or self.lastModified or "unknown") + "____________________________________________________astal_experiments._plus_website_changes.";
}

{ self, ... }:
{
  system.nixos.label = "need_to_fix_home-module.____________________________________________________________________" + "REV_" + toString (self.shortRev or self.dirtyShortRev or self.lastModified or "unknown") + "____________________________________________________astal_experiments._plus_website_changes.";
}

{ self, ... }:
{
  system.nixos.label = "need_to_fix_home-module.____________________________________________________________________" + "REV_" + toString (self.shortRev or self.dirtyShortRev or self.lastModified or "unknown") + "____________________________________________________________________need_to_fix_home-module.";
}

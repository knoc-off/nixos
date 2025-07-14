{ self, ... }:
{
  system.nixos.label = "cli-garbage_________________________________________________________________________________" + "REV_" + toString (self.shortRev or self.dirtyShortRev or self.lastModified or "unknown") + "____________________________________________________________________need_to_fix_home-module.";
}

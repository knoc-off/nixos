{ self, ... }:
{
  system.nixos.label = "update_and_nvim_breakup_____________________________________________________________________" + "REV_" + toString (self.shortRev or self.dirtyShortRev or self.lastModified or "unknown") + "_____________________________________________________________________update_and_nvim_breakup";
}

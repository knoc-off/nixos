{ self, ... }:
{
  system.nixos.label = "iso_stuff___________________________________________________________________________________" + "REV_" + toString (self.shortRev or self.dirtyShortRev or self.lastModified or "unknown") + "_____________________________________________________________________update_and_nvim_breakup";
}

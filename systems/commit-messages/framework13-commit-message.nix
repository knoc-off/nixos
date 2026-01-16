{ self, ... }:
{
  system.nixos.label = "Kanata_restart_trigger_ghostty_optimizations" + "REV_" + toString (self.shortRev or self.dirtyShortRev or self.lastModified or "unknown") + "update";
}

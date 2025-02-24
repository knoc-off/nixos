{ self, ... }:
{
  system.nixos.label = "work_in_progress____________________________________________________________________________" + "REV_" + toString (self.shortRev or self.dirtyShortRev or self.lastModified or "unknown") + "_________________________________________________________minecraft_changes._disable_waydroid";
}

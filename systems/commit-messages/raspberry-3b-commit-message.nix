{ self, ... }:
{
  system.nixos.label = "WIP:_gotten_quite_far.______________________________________________________________________" + "REV_" + toString (self.shortRev or self.dirtyShortRev or self.lastModified or "unknown") + "_________________________________________________________minecraft_changes._disable_waydroid";
}

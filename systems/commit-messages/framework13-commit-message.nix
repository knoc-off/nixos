{ self, ... }:
{
  system.nixos.label = "minecraft_changes._disable_waydroid_________________________________________________________" + "REV_" + toString (self.shortRev or self.dirtyShortRev or self.lastModified or "unknown") + "_________________________________________________________minecraft_changes._disable_waydroid";
}

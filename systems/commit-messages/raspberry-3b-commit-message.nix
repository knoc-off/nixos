{ self, ... }:
{
  system.nixos.label = "mkSystem__nixosSystem_-_for_darwin__________________________________________________________" + "REV_" + toString (self.shortRev or self.dirtyShortRev or self.lastModified or "unknown") + "_________________________________________________________minecraft_changes._disable_waydroid";
}

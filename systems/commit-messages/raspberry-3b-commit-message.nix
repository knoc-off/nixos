{ self, ... }:
{
  system.nixos.label = "buffer_swapping_in_bevy_shader______________________________________________________________" + "REV_" + toString (self.shortRev or self.dirtyShortRev or self.lastModified or "unknown") + "_________________________________________________________minecraft_changes._disable_waydroid";
}

{ self, ... }:
{
  system.nixos.label = "updated_bevy_animate_shader_________________________________________________________________" + "REV_" + toString (self.shortRev or self.dirtyShortRev or self.lastModified or "unknown") + "_____________________________________________________________________________big_restructure";
}

{ self, ... }:
{
  system.nixos.label = "updated_bevy_animate_shader_________________________________________________________________" + "REV_" + toString (self.shortRev or self.dirtyShortRev or self.lastModified or "unknown") + "_________________________________________________________________________imap_filter_removed";
}

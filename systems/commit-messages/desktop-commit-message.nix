{ self, ... }:
{
  system.nixos.label = "updated_bevy_animate_shader_________________________________________________________________" + "REV_" + toString (self.shortRev or self.dirtyShortRev or self.lastModified or "unknown") + "_____________________________________________________moving_to_new_version_of_nixpkgs._24.11";
}

{ self, ... }:
{
  system.nixos.label = "made_a_few_clones_of_bevy_to_test_stuff_____________________________________________________" + "REV_" + toString (self.shortRev or self.dirtyShortRev or self.lastModified or "unknown") + "_____________________________________________________moving_to_new_version_of_nixpkgs._24.11";
}

{ self, ... }:
{
  system.nixos.label = "website_overhaul_on_axum____________________________________________________________________" + "REV_" + toString (self.shortRev or self.dirtyShortRev or self.lastModified or "unknown") + "_____________________________________________________made_a_few_clones_of_bevy_to_test_stuff";
}

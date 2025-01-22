{ self, ... }:
{
  system.nixos.label = "big_axum_update_icons_now_are_optimized_and_pruned__________________________________________" + "REV_" + toString (self.shortRev or self.dirtyShortRev or self.lastModified or "unknown") + "_____________________________________________________________________________big_restructure";
}

{ self, ... }:
{
  system.nixos.label = "axum_changed_how_some_of_the_pruning_scripts_were_working___________________________________" + "REV_" + toString (self.shortRev or self.dirtyShortRev or self.lastModified or "unknown") + "_____________________________________________________________________________big_restructure";
}

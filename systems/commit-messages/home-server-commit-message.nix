{ self, ... }:
{
  system.nixos.label = "working_minimal_state_adaptible_____________________________________________________________" + "REV_" + toString (self.shortRev or self.dirtyShortRev or self.lastModified or "unknown") + "_____________________________________________________________________________big_restructure";
}

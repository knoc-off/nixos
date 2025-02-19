{ self, ... }:
{
  system.nixos.label = "working_minimal_state_adaptible_____________________________________________________________" + "REV_" + toString (self.shortRev or self.dirtyShortRev or self.lastModified or "unknown") + "___________________________________________________________website_changes_and_other_changes";
}

{ self, ... }:
{
  system.nixos.label = "working_state_issues_with_polling___________________________________________________________" + "REV_" + toString (self.shortRev or self.dirtyShortRev or self.lastModified or "unknown") + "_____________________________________________________________________________big_restructure";
}

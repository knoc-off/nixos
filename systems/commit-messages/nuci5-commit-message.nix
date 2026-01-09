{ self, ... }:
{
  system.nixos.label = "fiefox_css_changes_added_pre-commit_hooks_for_accidentally_commiting_binary_data." + "REV_" + toString (self.shortRev or self.dirtyShortRev or self.lastModified or "unknown") + "working_esp";
}

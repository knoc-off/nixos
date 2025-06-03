{ self, ... }:
{
  system.nixos.label = "updates_similify_layout_____________________________________________________________________" + "REV_" + toString (self.shortRev or self.dirtyShortRev or self.lastModified or "unknown") + "______________________________________new_firefox_profile_small_changes_to_framework_and_nuc";
}

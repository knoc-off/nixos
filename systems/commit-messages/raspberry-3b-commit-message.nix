{ self, ... }:
{
  system.nixos.label = "new_firefox_profile_small_changes_to_framework_and_nuc______________________________________" + "REV_" + toString (self.shortRev or self.dirtyShortRev or self.lastModified or "unknown") + "_________________________________________________________minecraft_changes._disable_waydroid";
}

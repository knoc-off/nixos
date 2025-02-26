{ self, ... }:
{
  system.nixos.label = "axum_tests__________________________________________________________________________________" + "REV_" + toString (self.shortRev or self.dirtyShortRev or self.lastModified or "unknown") + "___________________________________________________________website_changes_and_other_changes";
}

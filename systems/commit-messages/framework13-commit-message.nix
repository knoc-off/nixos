{ self, ... }:
{
  system.nixos.label = "working_upload_and_check.___________________________________________________________________" + "REV_" + toString (self.shortRev or self.dirtyShortRev or self.lastModified or "unknown") + "___________________________________________________________website_changes_and_other_changes";
}

{ self, ... }:
{
  system.nixos.label = "testing_new_commit_message__________________________________________________________________" + "REV_" + toString (self.shortRev or self.dirtyShortRev or self.lastModified or "unknown") + "_________________________________________________________________________imap_filter_removed";
}

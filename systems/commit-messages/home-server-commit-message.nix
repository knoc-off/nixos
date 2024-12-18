{ self, ... }:
{
  system.nixos.label = "testing_new_commit_message__________________________________________________________________" + "REV_" + toString (self.shortRev or self.dirtyShortRev or self.lastModified or "unknown") + "_____________________________________________________________________________big_restructure";
}

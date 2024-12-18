{ self, ... }:
{
  system.nixos.label = "testing_new_commit_message__________________________________________________________________" + "REV_" + toString (self.shortRev or self.dirtyShortRev or self.lastModified or "unknown") + "________________________________________________________lots_of_small_changes_mainly_cleanup";
}

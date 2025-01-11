{ self, ... }:
{
  system.nixos.label = "a_few_changes_mostly_to_the_desktop_environment_added_totem_media_player____________________" + "REV_" + toString (self.shortRev or self.dirtyShortRev or self.lastModified or "unknown") + "_____________________________________________________________________________big_restructure";
}

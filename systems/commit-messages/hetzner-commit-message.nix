{ self, ... }:
{
  system.nixos.label = "bevy_example________________________________________________________________________________" + "REV_" + toString (self.shortRev or self.dirtyShortRev or self.lastModified or "unknown") + "_________________________________________________________________________imap_filter_removed";
}

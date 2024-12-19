{ self, ... }:
{
  system.nixos.label = "cleanup_and_bevy____________________________________________________________________________" + "REV_" + toString (self.shortRev or self.dirtyShortRev or self.lastModified or "unknown") + "_____________________________________________________________________________big_restructure";
}

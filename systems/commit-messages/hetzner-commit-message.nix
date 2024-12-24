{ self, ... }:
{
  system.nixos.label = "assets_folder_______________________________________________________________________________" + "REV_" + toString (self.shortRev or self.dirtyShortRev or self.lastModified or "unknown") + "_________________________________________________________________________imap_filter_removed";
}

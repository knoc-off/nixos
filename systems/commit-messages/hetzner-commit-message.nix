{ self, ... }:
{
  system.nixos.label = "System_update_______________________________________________________________________________" + "REV_" + toString (self.shortRev or self.dirtyShortRev or self.lastModified or "unknown") + "_________________________________________________________________________imap_filter_removed";
}

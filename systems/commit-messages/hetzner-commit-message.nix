{ self, ... }:
{
  system.nixos.label = "gitignore_update____________________________________________________________________________" + "REV_" + toString (self.shortRev or self.dirtyShortRev or self.lastModified or "unknown") + "_________________________________________________________________________imap_filter_removed";
}

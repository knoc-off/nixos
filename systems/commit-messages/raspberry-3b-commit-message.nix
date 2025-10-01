{ self, ... }:
{
  system.nixos.label = "logiops_overhaul____________________________________________________________________________" + "REV_" + toString (self.shortRev or self.dirtyShortRev or self.lastModified or "unknown") + "___________________________________________________________________________________iso_stuff";
}

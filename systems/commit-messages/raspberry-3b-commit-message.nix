{ self, ... }:
{
  system.nixos.label = "quick_sync" + "REV_" + toString (self.shortRev or self.dirtyShortRev or self.lastModified or "unknown") + "iso_stuff";
}

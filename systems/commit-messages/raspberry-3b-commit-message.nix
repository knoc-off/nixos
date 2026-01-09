{ self, ... }:
{
  system.nixos.label = "firefox_sync" + "REV_" + toString (self.shortRev or self.dirtyShortRev or self.lastModified or "unknown") + "iso_stuff";
}

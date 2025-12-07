{ self, ... }:
{
  system.nixos.label = "cleanup" + "REV_" + toString (self.shortRev or self.dirtyShortRev or self.lastModified or "unknown") + "iso_stuff";
}

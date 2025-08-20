{ self, ... }:
{
  system.nixos.label = "iso_stuff___________________________________________________________________________________" + "REV_" + toString (self.shortRev or self.dirtyShortRev or self.lastModified or "unknown") + "___________________________________________________________________________________iso_stuff";
}

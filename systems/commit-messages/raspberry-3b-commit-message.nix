{ self, ... }:
{
  system.nixos.label = "fixes_______________________________________________________________________________________" + "REV_" + toString (self.shortRev or self.dirtyShortRev or self.lastModified or "unknown") + "___________________________________________________________________________________iso_stuff";
}

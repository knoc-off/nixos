{ self, ... }:
{
  system.nixos.label = "small_improvements__________________________________________________________________________" + "REV_" + toString (self.shortRev or self.dirtyShortRev or self.lastModified or "unknown") + "___________________________________________________________________________________iso_stuff";
}

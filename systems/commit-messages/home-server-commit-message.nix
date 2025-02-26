{ self, ... }:
{
  system.nixos.label = "cool_little_example_________________________________________________________________________" + "REV_" + toString (self.shortRev or self.dirtyShortRev or self.lastModified or "unknown") + "_____________________________________________________________________________big_restructure";
}

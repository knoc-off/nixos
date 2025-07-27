{ self, ... }:
{
  system.nixos.label = "quick_fix___________________________________________________________________________________" + "REV_" + toString (self.shortRev or self.dirtyShortRev or self.lastModified or "unknown") + "________________________________________________________________________________________nvim";
}

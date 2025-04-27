{ self, ... }:
{
  system.nixos.label = "quick_______________________________________________________________________________________" + "REV_" + toString (self.shortRev or self.dirtyShortRev or self.lastModified or "unknown") + "___________________________________________________________________________________wireguard";
}

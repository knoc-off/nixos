{ self, ... }:
{
  system.nixos.label = "wireguard___________________________________________________________________________________" + "REV_" + toString (self.shortRev or self.dirtyShortRev or self.lastModified or "unknown") + "___________________________________________________________________________________wireguard";
}

{ self, ... }:
{
  system.nixos.label = "merge" + "REV_" + toString (self.shortRev or self.dirtyShortRev or self.lastModified or "unknown") + "quick_sync";
}

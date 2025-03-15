{ self, ... }:
{
  system.nixos.label = "fish________________________________________________________________________________________" + "REV_" + toString (self.shortRev or self.dirtyShortRev or self.lastModified or "unknown") + "________________________________________________________________________________________fish";
}

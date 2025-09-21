{ self, ... }:
{
  system.nixos.label = "idk_________________________________________________________________________________________" + "REV_" + toString (self.shortRev or self.dirtyShortRev or self.lastModified or "unknown") + "____________________________________________________________________________Updated_to_25.05";
}

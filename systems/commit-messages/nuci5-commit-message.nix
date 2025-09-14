{ self, ... }:
{
  system.nixos.label = "small_improvements__________________________________________________________________________" + "REV_" + toString (self.shortRev or self.dirtyShortRev or self.lastModified or "unknown") + "____________________________________________________________________________Updated_to_25.05";
}

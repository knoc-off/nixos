{ self, ... }:
{
  system.nixos.label = "gtk_________________________________________________________________________________________" + "REV_" + toString (self.shortRev or self.dirtyShortRev or self.lastModified or "unknown") + "_________________________________________________________________________________________gtk";
}

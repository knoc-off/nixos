{ self, ... }:
{
  system.nixos.label = "fixed_stupid_rust_analyzer_error____________________________________________________________" + "REV_" + toString (self.shortRev or self.dirtyShortRev or self.lastModified or "unknown") + "_____________________________________________________________________________big_restructure";
}

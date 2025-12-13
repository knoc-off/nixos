{ self, ... }:
{
  system.nixos.label = "impure_unsandboxed_build_for_microcad" + "REV_" + toString (self.shortRev or self.dirtyShortRev or self.lastModified or "unknown") + "big_restructure";
}

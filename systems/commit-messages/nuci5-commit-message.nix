{ self, ... }:
{
  system.nixos.label = "microcad" + "REV_" + toString (self.shortRev or self.dirtyShortRev or self.lastModified or "unknown") + "working_esp";
}

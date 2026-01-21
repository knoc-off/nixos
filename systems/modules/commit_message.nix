{self, ...}: {
  system.nixos.label = self.shortRev or self.dirtyShortRev or "unknown";
}

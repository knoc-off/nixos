{ self, ... }:
{
  system.nixos.label = "kanata" + "REV_" + toString (self.shortRev or self.dirtyShortRev or self.lastModified or "unknown") + "relm_layershell";
}

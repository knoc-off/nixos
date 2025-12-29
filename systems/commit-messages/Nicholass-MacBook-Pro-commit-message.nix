{ self, ... }:
{
  system.nixos.label = "relm_layershell" + "REV_" + toString (self.shortRev or self.dirtyShortRev or self.lastModified or "unknown") + "quick_sync";
}

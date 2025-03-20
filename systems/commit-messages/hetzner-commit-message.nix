{ self, ... }:
{
  system.nixos.label = "neovim_changes______________________________________________________________________________" + "REV_" + toString (self.shortRev or self.dirtyShortRev or self.lastModified or "unknown") + "___________________________________________________________________________________wireguard";
}

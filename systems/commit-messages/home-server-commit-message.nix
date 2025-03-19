{ self, ... }:
{
  system.nixos.label = "Refactor:_Remove_which-key_configurations_from_neovim_config________________________________" + "REV_" + toString (self.shortRev or self.dirtyShortRev or self.lastModified or "unknown") + "_____________________________________________________________________________big_restructure";
}

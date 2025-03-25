{ self, ... }:
{
  system.nixos.label = "keyboard_macros_for_umlauts_________________________________________________________________" + "REV_" + toString (self.shortRev or self.dirtyShortRev or self.lastModified or "unknown") + "_____________________________________________________moving_to_new_version_of_nixpkgs._24.11";
}

{ self, ... }:
{
  system.nixos.label = "old_parsing_algo.___________________________________________________________________________" + "REV_" + toString (self.shortRev or self.dirtyShortRev or self.lastModified or "unknown") + "_____________________________________________________moving_to_new_version_of_nixpkgs._24.11";
}

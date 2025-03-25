{ self, ... }:
{
  system.nixos.label = "nvim_whichkey_migration.____________________________________________________________________" + "REV_" + toString (self.shortRev or self.dirtyShortRev or self.lastModified or "unknown") + "_____________________________________________________moving_to_new_version_of_nixpkgs._24.11";
}

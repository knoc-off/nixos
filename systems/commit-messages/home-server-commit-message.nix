{ self, ... }:
{
  system.nixos.label = "nvim_whichkey_migration.____________________________________________________________________" + "REV_" + toString (self.shortRev or self.dirtyShortRev or self.lastModified or "unknown") + "_____________________________________________________________________________big_restructure";
}

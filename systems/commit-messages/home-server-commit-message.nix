{ self, ... }:
{
  system.nixos.label = "refactor:_Update_which-key_config_to_use_spec_instead_of_registrations______________________" + "REV_" + toString (self.shortRev or self.dirtyShortRev or self.lastModified or "unknown") + "_____________________________________________________________________________big_restructure";
}

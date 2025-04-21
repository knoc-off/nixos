{ self, ... }:
{
  system.nixos.label = "fix:_Pass_extra_arguments_to_theme_function_________________________________________________" + "REV_" + toString (self.shortRev or self.dirtyShortRev or self.lastModified or "unknown") + "_________________________________________________________________________________________gtk";
}

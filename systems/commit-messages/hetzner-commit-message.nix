{ self, ... }:
{
  system.nixos.label = "hyprkan_fixes_for_caps" + "REV_" + toString (self.shortRev or self.dirtyShortRev or self.lastModified or "unknown") + "relm_layershell";
}

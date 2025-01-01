{ self, ... }:
{
  system.nixos.label = "small_changes_shader_is_now_warp____________________________________________________________" + "REV_" + toString (self.shortRev or self.dirtyShortRev or self.lastModified or "unknown") + "_____________________________________________________________________________big_restructure";
}

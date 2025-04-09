{ self, ... }:
{
  system.nixos.label = "refactor:_Use_theme_variables_directly_in_kitty_config______________________________________" + "REV_" + toString (self.shortRev or self.dirtyShortRev or self.lastModified or "unknown") + "___________________________________________________________________________________wireguard";
}

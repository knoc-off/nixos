{ self, ... }:
{
  system.nixos.label = "quick_neovim_push___________________________________________________________________________" + "REV_" + toString (self.shortRev or self.dirtyShortRev or self.lastModified or "unknown") + "____________________________________________________astal_experiments._plus_website_changes.";
}

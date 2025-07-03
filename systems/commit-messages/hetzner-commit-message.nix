{ self, ... }:
{
  system.nixos.label = "mkSystem__nixosSystem_-_for_darwin__________________________________________________________" + "REV_" + toString (self.shortRev or self.dirtyShortRev or self.lastModified or "unknown") + "____________________________________________________astal_experiments._plus_website_changes.";
}

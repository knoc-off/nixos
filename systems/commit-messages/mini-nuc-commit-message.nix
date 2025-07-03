{ self, ... }:
{
  system.nixos.label = "mkSystem__nixosSystem_-_for_darwin__________________________________________________________" + "REV_" + toString (self.shortRev or self.dirtyShortRev or self.lastModified or "unknown") + "_________________________________________________________________________________nuci5_added";
}

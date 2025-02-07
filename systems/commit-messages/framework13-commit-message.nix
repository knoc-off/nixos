{ self, ... }:
{
  system.nixos.label = "undo_some_changes___________________________________________________________________________" + "REV_" + toString (self.shortRev or self.dirtyShortRev or self.lastModified or "unknown") + "_______________________________________________________________________fully_functional_site";
}

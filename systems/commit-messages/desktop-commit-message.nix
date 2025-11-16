{ self, ... }:
{
  system.nixos.label = "TV_box_updated" + "REV_" + toString (self.shortRev or self.dirtyShortRev or self.lastModified or "unknown") + "Updated_to_25.05";
}

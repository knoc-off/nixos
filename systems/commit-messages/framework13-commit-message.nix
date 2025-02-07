{ self, ... }:
{
  system.nixos.label = "websute_updated_blogs_are_much_nicer._______________________________________________________" + "REV_" + toString (self.shortRev or self.dirtyShortRev or self.lastModified or "unknown") + "_______________________________________________________________________fully_functional_site";
}

{ self, ... }:
{
  system.nixos.label = "fully_functional_site_______________________________________________________________________" + "REV_" + toString (self.shortRev or self.dirtyShortRev or self.lastModified or "unknown") + "______________________________________added_blogging_ability_to_the_website._simple_markdown";
}

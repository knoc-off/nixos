{ self, ... }:
{
  system.nixos.label = "WIP:_gotten_quite_far.______________________________________________________________________" + "REV_" + toString (self.shortRev or self.dirtyShortRev or self.lastModified or "unknown") + "______________________________________added_blogging_ability_to_the_website._simple_markdown";
}

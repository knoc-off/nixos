{ self, ... }:
{
  system.nixos.label = "fix:_Start_search_input_with_blank_instead_of_previous_term_________________________________" + "REV_" + toString (self.shortRev or self.dirtyShortRev or self.lastModified or "unknown") + "_____________________________________________________________________________big_restructure";
}

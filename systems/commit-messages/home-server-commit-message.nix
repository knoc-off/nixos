{ self, ... }:
{
  system.nixos.label = "Working_marki_markdown_to_anki______________________________________________________________" + "REV_" + toString (self.shortRev or self.dirtyShortRev or self.lastModified or "unknown") + "_____________________________________________________________________________big_restructure";
}

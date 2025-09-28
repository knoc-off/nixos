{ self, ... }:
{
  system.nixos.label = "refactor_and_more___________________________________________________________________________" + "REV_" + toString (self.shortRev or self.dirtyShortRev or self.lastModified or "unknown") + "___________________________________________________________________________refactor_and_more";
}

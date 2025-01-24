{ self, ... }:
{
  system.nixos.label = "website_changes.____________________________________________________________________________" + "REV_" + toString (self.shortRev or self.dirtyShortRev or self.lastModified or "unknown") + "_______________________________________________________________________________System_update";
}

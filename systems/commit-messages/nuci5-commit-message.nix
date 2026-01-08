{ self, ... }:
{
  system.nixos.label = "firefox_extension_style" + "REV_" + toString (self.shortRev or self.dirtyShortRev or self.lastModified or "unknown") + "working_esp";
}

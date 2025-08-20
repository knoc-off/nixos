{ self, ... }:
{
  system.nixos.label = "iso_stuff___________________________________________________________________________________" + "REV_" + toString (self.shortRev or self.dirtyShortRev or self.lastModified or "unknown") + "______________________________________________________________feat:_enabled_sops_and_api_key";
}

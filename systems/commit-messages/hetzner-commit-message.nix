{ self, ... }:
{
  system.nixos.label = "sync_wasm_stuff" + "REV_" + toString (self.shortRev or self.dirtyShortRev or self.lastModified or "unknown") + "astal_experiments._plus_website_changes.";
}

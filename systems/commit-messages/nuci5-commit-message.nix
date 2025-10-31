{ self, ... }:
{
  system.nixos.label = "sync_wasm_stuff" + "REV_" + toString (self.shortRev or self.dirtyShortRev or self.lastModified or "unknown") + "Updated_to_25.05";
}

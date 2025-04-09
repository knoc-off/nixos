{ self, ... }:
{
  system.nixos.label = "style:_Prepend__to_hex_color_values_in_kitty_config_________________________________________" + "REV_" + toString (self.shortRev or self.dirtyShortRev or self.lastModified or "unknown") + "___________________________________________________________________________________wireguard";
}

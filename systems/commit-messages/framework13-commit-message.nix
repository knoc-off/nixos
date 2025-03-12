{ self, ... }:
{
  system.nixos.label = "interesting_function_stuff__________________________________________________________________" + "REV_" + toString (self.shortRev or self.dirtyShortRev or self.lastModified or "unknown") + "__________________________________________________________________interesting_function_stuff";
}

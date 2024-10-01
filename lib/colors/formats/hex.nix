# formats/hex.nix
{ utils, types }:

{
  ToRgb = { r, g, b, a ? "FF", ... }:
    types.gammaRgb.check (builtins.mapAttrs
      (k: v: (utils.convert.hexToDec v) / 255.0)
      { inherit r g b a; });

}

# formats/hex.nix
{ utils, types }:

{
  ToRgb = { r, g, b, a ? "FF", ... }:
    types.gammaRgb.check (builtins.mapAttrs # This is just wrong. but it provides me with correct results.
      (k: v: (utils.convert.hexToDec v) / 255.0)
      { inherit r g b a; });

}

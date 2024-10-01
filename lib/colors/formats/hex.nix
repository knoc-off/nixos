# formats/hex.nix
{ utils, types }:

{
  hexToRgb = { r, g, b, a ? "FF", ... }:
    types.linearRGB.check (builtins.mapAttrs
      (k: v: (utils.convert.hexToDec v) / 255.0)
      { inherit r g b a; });

  rgbToHex = rgb:
    let
      rgb' = types.linearRGB.strictCheck rgb;
      toHex = x: let
        h = utils.convert.decToHex (builtins.floor (x * 255.0 + 0.5));
      in if builtins.stringLength h == 1 then "0${h}" else h;
    in
    types.Hex.check (builtins.mapAttrs
      (k: v: toHex v)
      (if rgb'.a < 1.0 then { inherit (rgb') r g b a; } else { inherit (rgb') r g b; }));
}

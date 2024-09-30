# formats/hex.nix
{ utils, types }:

{
  hexToRgb = { r, g, b, a ? "FF", meta ? {} }:
    types.RGB.check (builtins.mapAttrs
      (k: v: (utils.convert.hexToDec v) / 255.0)
      { inherit r g b a; });


  rgbToHex = { r, g, b, a ? 1.0, meta ? {} }:
    let
      toHex = x: let
        h = utils.convert.decToHex (builtins.floor (x * 255.0 + 0.5));
      in if builtins.stringLength h == 1 then "0${h}" else h;
    in
    types.Hex.check (builtins.mapAttrs
      (k: v: toHex v)
      (if a < 1.0 then { inherit r g b a; } else { inherit r g b; }));
}

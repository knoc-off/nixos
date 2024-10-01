# formats/rgb.nix
{ math, utils, types }:
let
  # Gamma correction: sRGB to linear
  gammaToLinear = c:
    if c >= 0.04045
    then math.powFloat((c + 0.055) / 1.055) 2.4
    else c / 12.92;

in
{
  ToLinear = rgb:
    let
      rgb' = types.gammaRgb.strictCheck rgb;
    in
    types.linearRgb.check (builtins.mapAttrs
      (k: v: if k == "a" then v else utils.clampF (gammaToLinear v) 0.0 1.0)
      { inherit (rgb') r g b a; });

  ToHex = rgb:
    let
      rgb' = types.gammaRgb.strictCheck rgb;
      toHex = x: let
        h = utils.convert.decToHex (builtins.floor (x * 255.0 + 0.5));
      in if builtins.stringLength h == 1 then "0${h}" else h;
    in
    types.Hex.check (builtins.mapAttrs
      (k: v: toHex v)
      (if rgb'.a < 1.0 then { inherit (rgb') r g b a; } else { inherit (rgb') r g b; }));
}

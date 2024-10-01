# formats/rgb.nix
{ math, utils, types }:
let
  # Gamma correction: sRGB to linear
  gammaToLinear = c:
    if c >= 0.04045
    then math.powFloat((c + 0.055) / 1.055) 2.4
    else c / 12.92;

  # Gamma correction: linear to sRGB
  linearToGamma = c:
    if c >= 0.0031308
    then 1.055 * math.powFloat c (1 / 2.4) - 0.055
    else 12.92 * c;
in
{
  gammaRgbToLinear = rgb:
    let
      rgb' = types.linearRGB.strictCheck rgb;
    in
    types.sRGB.check (builtins.mapAttrs
      (k: v: if k == "a" then v else utils.clampF (gammaToLinear v) 0.0 1.0)
      { inherit (rgb') r g b a; });

  linearToGammaRgb = rgb:
    let
      rgb' = types.sRGB.strictCheck rgb;
    in
    types.sRGB.check (builtins.mapAttrs
      (k: v: if k == "a" then v else utils.clampF (linearToGamma v) 0.0 1.0)
      { inherit (rgb') r g b a; });
}

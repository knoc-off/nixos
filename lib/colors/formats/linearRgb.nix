# formats/oklab.nix
{ math, utils, types }:
let
  # Gamma correction: linear to sRGB
  linearToGamma = c:
    if c >= 0.0031308
    then 1.055 * math.powFloat c (1 / 2.4) - 0.055
    else 12.92 * c;
in

{
  # Linear RGB to CIE XYZ conversion
  ToXyz = { r, g, b, a ? 1, meta ? {} }@rgb:
    let
      rgb' = types.gammaRgb.check rgb;
    in
    types.XYZ.check {
      X = 0.4124564 * rgb'.r + 0.3575761 * rgb'.g + 0.1804375 * rgb'.b;
      Y = 0.2126729 * rgb'.r + 0.7151522 * rgb'.g + 0.0721750 * rgb'.b;
      Z = 0.0193339 * rgb'.r + 0.1191920 * rgb'.g + 0.9503041 * rgb'.b;
      alpha = rgb'.a;
    };

  ToGammaRgb = rgb:
    let
      rgb' = types.linearRgb.strictCheck rgb;
    in
    types.gammaRgb.check (builtins.mapAttrs
      (k: v: if k == "a" then v else utils.clampF (linearToGamma v) 0.0 1.0)
      { inherit (rgb') r g b a; });
}

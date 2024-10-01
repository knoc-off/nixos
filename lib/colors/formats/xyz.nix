# formats/oklab.nix
{ math, lib, utils, types, srgb }:

rec {
  # Linear RGB to CIE XYZ conversion
  linearRgbToXyz = { r, g, b, a ? 1, meta ? {} }@rgb:
    let
      rgb' = types.sRGB.check rgb;
    in
    types.XYZ.check {
      X = 0.4124564 * rgb'.r + 0.3575761 * rgb'.g + 0.1804375 * rgb'.b;
      Y = 0.2126729 * rgb'.r + 0.7151522 * rgb'.g + 0.0721750 * rgb'.b;
      Z = 0.0193339 * rgb'.r + 0.1191920 * rgb'.g + 0.9503041 * rgb'.b;
      alpha = rgb'.a;
    };

  # CIE XYZ to Oklab conversion
  xyzToOklab = { X, Y, Z, alpha ? 1, meta ? {} }@xyz: let
    l = 0.8189330101 * xyz.X + 0.3618667424 * xyz.Y - 0.1288597137 * xyz.Z;
    m = 0.0329845436 * xyz.X + 0.9293118715 * xyz.Y + 0.0361456387 * xyz.Z;
    s = 0.0482003018 * xyz.X + 0.2643662691 * xyz.Y + 0.6338517070 * xyz.Z;

    l_ = math.cbrt l;
    m_ = math.cbrt m;
    s_ = math.cbrt s;

    L = 0.2104542553 * l_ + 0.7936177850 * m_ - 0.0040720468 * s_;
    a = 1.9779984951 * l_ - 2.4285922050 * m_ + 0.4505937099 * s_;
    b = 0.0259040371 * l_ + 0.7827717662 * m_ - 0.8086757660 * s_;
  in types.Oklab.check {
    inherit L a b;
    alpha = xyz.alpha;
  };



  ToOklch = oklab:
    let
      lab = types.Oklab.strictCheck oklab;
      C = math.sqrt (lab.a * lab.a + lab.b * lab.b);
      h = math.atan2 lab.b lab.a;
      h_degrees = h * 180 / math.pi;
      h_positive = if h_degrees < 0 then h_degrees + 360 else h_degrees;
      result = {
        L = lab.L;
        C = C;
        h = h_positive;
      };
    in
    types.Oklch.check (result // (if lab ? alpha then { inherit (lab) alpha; } else { alpha = 1.0; }));


  # Combined sRGB to Oklab conversion
  rgbToOklab = rgb:
    xyzToOklab (linearRgbToXyz (srgb.srgbToLinearRgb rgb));

  # Oklab to CIE XYZ conversion
  oklabToXyz = { L, a, b, alpha ? 1, meta ? {} }@lab: let
    l_ = lab.L + 0.3963377774 * lab.a + 0.2158037573 * lab.b;
    m_ = lab.L - 0.1055613458 * lab.a - 0.0638541728 * lab.b;
    s_ = lab.L - 0.0894841775 * lab.a - 1.2914855480 * lab.b;

    l = math.pow l_ 3;
    m = math.pow m_ 3;
    s = math.pow s_ 3;
  in types.XYZ.check {
    X = 1.2270138511 * l - 0.5577999807 * m + 0.2812561490 * s;
    Y = -0.0405801784 * l + 1.1122568696 * m - 0.0716766787 * s;
    Z = -0.0763812845 * l - 0.4214819784 * m + 1.5861632204 * s;
    alpha = lab.alpha;
  };

  # CIE XYZ to Linear RGB conversion
  xyzToLinearRgb = { X, Y, Z, alpha ? 1, meta ? {} }@xyz: types.sRGB.check {
    r = 3.2404542 * xyz.X - 1.5371385 * xyz.Y - 0.4985314 * xyz.Z;
    g = -0.9692660 * xyz.X + 1.8760108 * xyz.Y + 0.0415560 * xyz.Z;
    b = 0.0556434 * xyz.X - 0.2040259 * xyz.Y + 1.0572252 * xyz.Z;
    a = xyz.alpha;
  };

  # Combined Oklab to sRGB conversion
  oklabToRgb = lab:
    let
      lab' = types.Oklab.strictCheck lab;
    in
    types.linearRGB.check ( srgb.linearToGammaRgb (xyzToLinearRgb (oklabToXyz lab')));
}

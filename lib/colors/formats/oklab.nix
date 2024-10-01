# formats/oklab.nix
{ math, lib, utils, types, linearRgb, xyz }:

rec {
  # Combined Oklab to sRGB conversion
  ToRgb = lab:
    let
      lab' = types.Oklab.strictCheck lab;
    in
    types.gammaRgb.check ( linearRgb.ToGammaRgb (xyz.ToLinearRgb (ToXyz lab')));

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

  # Oklab to CIE XYZ conversion
  ToXyz = { L, a, b, alpha ? 1, meta ? {} }@lab: let
    l_ = lab.L + 0.3963377774 * lab.a + 0.2158037573 * lab.b;
    m_ = lab.L - 0.1055613458 * lab.a - 0.0638541728 * lab.b;
    s_ = lab.L - 0.0894841775 * lab.a - 1.2914855480 * lab.b;

    l = math.pow l_ 3;
    m = math.pow m_ 3;
    s = math.pow s_ 3;
  in types.XYZ.check {
    X = math.clamp (1.2270138511 * l - 0.5577999807 * m + 0.2812561490 * s) 0 0.95048;
    Y = math.clamp (-0.0405801784 * l + 1.1122568696 * m - 0.0716766787 * s) 0 1.00001;
    Z = math.clamp (-0.0763812845 * l - 0.4214819784 * m + 1.5861632204 * s) 0 1.08906;
    alpha = lab.alpha;
  };
}
#X = v: isBetween v 0 0.95048;
#Y = v: isBetween v 0 1.00001;
#Z = v: isBetween v 0 1.08906;

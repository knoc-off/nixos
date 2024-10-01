# formats/oklch.nix
{ math, utils, types }:
{

  oklabToOklch = oklab:
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

  oklchToOklab = oklch:
    let
      lch = types.Oklch.strictCheck oklch;
      h_radians = lch.h * math.pi / 180;
      result = {
        L = lch.L;
        a = lch.C * math.cos h_radians;
        b = lch.C * math.sin h_radians;
      };
    in
    types.Oklab.check (result // (if lch ? alpha then { inherit (lch) alpha; } else { alpha = 1.0; }));

}

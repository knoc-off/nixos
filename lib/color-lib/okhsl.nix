# okhsl.nix
{ core, math, oklab }:
with core;
with math;
with oklab; rec {

  toRGB = { h, s, l }:
    let
      a_ = cos (2 * pi * h);
      b_ = sin (2 * pi * h);
      L = toeInv (clamp l 0.0 1.0);
      Cs = getCs L a_ b_;
      C = if s < 0.8 then
        s * 0.8 * Cs.C_0
      else
        Cs.C_mid + (s - 0.8) * 0.2 * (Cs.C_max - Cs.C_mid);
    in oklabToLinearSRGB {
      L = L;
      a = C * a_;
      b = C * b_;
      alpha = 1.0;
    };

  # okhsl.nix
  fromRGB = { r, g, b, a ? 1.0 }:
    let
      lab = linearSRGBToOklab { inherit r g b a; };
      C = sqrt (lab.a * lab.a + lab.b * lab.b);
      h = if C == 0 then 0 else 0.5 + 0.5 * atan2 (-lab.b) (-lab.a) / pi;
      Cs = if C == 0 then {
        C_0 = 0;
        C_mid = 0;
        C_max = 0;
      } else
        getCs lab.L (lab.a / C) (lab.b / C);
      s = if C == 0 then
        0
      else if C < Cs.C_mid then
        C / (0.8 * Cs.C_0)
      else
        0.8 + 0.2 * (C - Cs.C_mid) / (Cs.C_max - Cs.C_mid);
      l = toe lab.L;
    in { inherit h s l; };

}

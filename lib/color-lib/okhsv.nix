# color-lib/okhsv.nix
{ core, math, oklab }:
with core;
with math;
with oklab; rec {

  toRGB = { h, s, v }:
    let
      a_ = cos (2 * pi * h);
      b_ = sin (2 * pi * h);
      stMax = getSTMax a_ b_;
      S_max = stMax.S;
      #T_max = stMax.T;
      #T_max = safeDiv (abs cusp.C) (1 - cusp.L + epsilon);
      T_max = abs (cusp.C) / (1 - cusp.L);
      k = 1 - 0.5 / (S_max + epsilon);
      L_v = 1 - s * 0.5 / (0.5 + T_max - T_max * k * s + epsilon);
      C_v = s * T_max * 0.5 / (0.5 + T_max - T_max * k * s + epsilon);
      L = clamp (v * L_v) 0.0 1.0;
      C = clamp (v * C_v) 0.0 1.0;
    in oklabToLinearSRGB {
      L = L;
      a = C * a_;
      b = C * b_;
      alpha = 1.0;
    };

  fromRGB = { r, g, b, a ? 1.0 }:
    let
      # Linearize the sRGB input
      linearRGB = {
        r = srgbTransferInv r;
        g = srgbTransferInv g;
        b = srgbTransferInv b;
        a = a;
      };
      lab = linearSRGBToOklab linearRGB;
      L = lab.L;
      C = sqrt (lab.a * lab.a + lab.b * lab.b);
      h = if C < epsilon then 0.0
          else 0.5 + 0.5 * atan2 (-lab.b) (-lab.a) / pi;

      a_norm = if C < epsilon then 0.0 else lab.a / C;
      b_norm = if C < epsilon then 0.0 else lab.b / C;
      stMax = getSTMax a_norm b_norm;
      S_max = abs stMax.S;
      S0 = 0.5;
      k = 1 - S0 / (S_max + epsilon);
      T_max = stMax.T;

      # if T_max is zero then force t to 1
      t = if T_max == 0.0 then 1.0 else T_max / (C + L * T_max + epsilon);
      L_v = t * L;
      C_v = t * C;

      L_vt = toeInv L_v;
      C_vt = if L_v == 0.0 then 0.0 else C_v * L_vt / L_v;
      rgb_scale = oklabToLinearSRGB {
        L = L_vt;
        a = a_norm * C_vt;
        b = b_norm * C_vt;
        alpha = 1.0;
      };
      scale_L = cbrt (safeDiv 1.0 (max (max rgb_scale.r rgb_scale.g) rgb_scale.b));
      L_lin = L / scale_L;
      C_lin = C / scale_L;

      L_final = toe L_lin;
      C_final = if L_lin == 0.0 then 0.0 else C_lin * toe L_lin / L_lin;
      v = if L_v == 0.0 then 0.0 else L_final / L_v;

      s = if T_max == 0.0 then (if C > epsilon then 1.0 else 0.0)
          else ((S0 + T_max) * C_v)
               / ((T_max * S0) + T_max * k * C_v + epsilon);
    in {
      h = clamp h 0.0 1.0;
      s = clamp s 0.0 1.0;
      v = clamp v 0.0 1.0;
      alpha = a;
    };
}


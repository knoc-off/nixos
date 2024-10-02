# formats/oklch.nix
{ math, utils, types }:
{
  ToOklab = oklch:
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

  ToOkhsl = oklch:
    let
      toe = x:
        let
          k1 = 0.206;
          k2 = 0.03;
          k3 = (1.0 + k1) / (1.0 + k2);
        in 0.5 * (k3 * x - k1 + math.sqrt ((k3 * x - k1) * (k3 * x - k1) + 4.0 * k2 * k3 * x));

      toe_inv = x:
        let
          k1 = 0.206;
          k2 = 0.03;
          k3 = (1.0 + k1) / (1.0 + k2);
        in (x * x + k1 * x) / (k3 * (x + k2));

      computeCs = L:
        let
          t = math.cbrt L;
        in {
          Cmax = t * (2.0 - t) / 2.0;
          Smax = t * (2.0 - t) / (2.0 * L);
        };

      lch = types.Oklch.strictCheck oklch;
      cs = computeCs lch.L;
      S = (if lch.C == 0.0 then 0.0 else lch.C / cs.Cmax);

    in
    types.Okhsl.check {
      h = lch.h;
      s = toe S;
      l = toe lch.L;
    };

    # Conversion from OKLCH to OKHSV
  ToOkhsv = oklch:
    let
      L = oklch.L;
      C = oklch.C;
      h = oklch.h;  # Hue in degrees [0, 360)

      ST_max = math.computeSTmax L;
      S_max = ST_max.S;
      T_max = ST_max.T;
      S_0 = 0.5;
      #k = 1.0 - S_0 / S_max;
      k = if S_max > S_0 then 1.0 - S_0 / S_max else 0.0;

      # Invert the gamut assumption to find original S and T
      S = (C * (S_0 + T_max - T_max * k)) / (T_max * S_0);
      V = L / (1.0 - (S * S_0) / (S_0 + T_max - T_max * k));

      # Clamp the results to valid ranges
      S_clamped = math.clamp S 0.0 1.0;
      V_clamped = math.clamp V 0.0 1.0;
      h_clamped = math.mod h 360.0;

    in
      types.Okhsv.check {
        h = h_clamped;
        s = S_clamped;
        v = V_clamped;
      };

  computeSTmax = L:
    let
      t = L / (1 - L);
      ST_max_S = t / (1 + t);
      ST_max_T = ST_max_S / t;
    in {
      S = ST_max_S;
      T = ST_max_T;
    };
}

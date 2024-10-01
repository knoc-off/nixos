# formats/oklch_okhsl.nix
{ math, lib, utils, types }:
let
  # Helper functions
  toe = x:
    let
      k1 = 0.206;
      k2 = 0.03;
      k3 = (1.0 + k1) / (1.0 + k2);
    in 0.5 * (k3 * x - k1 + math.sqrt ((math.powFloat (k3 * x - k1) 2) + (4.0 * k2 * k3 * x)));

  toe_inv = x:
    let
      k1 = 0.206;
      k2 = 0.03;
      k3 = (1.0 + k1) / (1.0 + k2);
    in (x * x + k1 * x) / (k3 * (x + k2));

  # Function to calculate Saturation correctly
  calculateSaturation = { C, L }:
    let
      Cmax = 1.0 - math.abs (2.0 * L - 1.0);
    in
      if Cmax > 0.0 then C / Cmax else 0.0;

in
{
  oklchToOkhsl = oklch:
    let
      lch = types.Oklch.strictCheck oklch;
      l_mapped = toe lch.L;  # Apply the toe function to lightness
      S = calculateSaturation { C = lch.C; L = lch.L; };
    in
      types.Okhsl.check {
        h = lch.h;
        s = S;
        l = l_mapped;
      };

  okhslToOklch = okhsl:
    let
      olhsl = types.Okhsl.strictCheck okhsl;
      L_linear = toe_inv olhsl.l;  # Invert the toe function to get original lightness
      Cmax = 1.0 - math.abs (2.0 * L_linear - 1.0);
      C = if Cmax > 0.0 then olhsl.s * Cmax else 0.0;
    in
      types.Oklch.check {
        L = L_linear;
        C = C;
        h = olhsl.h;
      };
}

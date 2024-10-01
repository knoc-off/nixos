# formats/oklch_okhsl.nix
{ math, lib, utils, types }:
let
  # Helper functions (reuse from your existing code)
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

in
{

  ToOklch = okhsl:
    let
      hsl = types.Okhsl.strictCheck okhsl;
      L = toe_inv hsl.l;
      cs = computeCs L;
      S = toe_inv hsl.s;
      C = S * cs.Cmax;
    in
    types.Oklch.check {
      L = L;
      C = C;
      h = hsl.h;
    };
}

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




      lch = types.Oklch.strictCheck oklch;
      cs = computeCs lch.L;
      S = if lch.C == 0.0 then 0.0 else lch.C / cs.Cmax;
    in
    types.Okhsl.check {
      h = lch.h;
      s = toe S;
      l = toe lch.L;
    };
}

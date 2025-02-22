# oklab.nix
{ core, math }:
with core;
with math; rec {
  linearSRGBToOklab = { r, g, b, a ? 1.0 }:
    let
      l = 0.4122214708 * r + 0.5363325363 * g + 5.14459929e-2 * b;
      m = 0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b;
      s = 8.83024619e-2 * r + 0.2817188376 * g + 0.6299787005 * b;
      l_ = cbrt l;
      m_ = cbrt m;
      s_ = cbrt s;
    in {
      L = 0.2104542553 * l_ + 0.793617785 * m_ - 4.0720468e-3 * s_;
      a = 1.9779984951 * l_ - 2.428592205 * m_ + 0.4505937099 * s_;
      b = 2.59040371e-2 * l_ + 0.7827717662 * m_ - 0.808675766 * s_;
      alpha = a;
    };

  oklabToLinearSRGB = { L, a, b, alpha ? 1.0 }:
    let
      l_ = L + 0.3963377774 * a + 0.2158037573 * b;
      m_ = L - 0.1055613458 * a - 6.38541728e-2 * b;
      s_ = L - 8.94841775e-2 * a - 1.291485548 * b;
      l = l_ * l_ * l_;
      m = m_ * m_ * m_;
      s = s_ * s_ * s_;
    in {
      r = clamp (4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s) 0 1;
      g = clamp (-1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s) 0 1;
      b = clamp (-4.1960863e-3 * l - 0.7034186147 * m + 1.707614701 * s) 0 1;
      a = alpha;
    };

  oklabToLCH = { L, a, b, alpha ? 1.0 }:
    let
      c = sqrt (a * a + b * b);
      h = atan2 b a;
    in { inherit L c h alpha; };

  lchToOklab = { L, c, h, alpha ? 1.0 }: {
    a = c * cos h;
    b = c * sin h;
    inherit L alpha;
  };

  # helpers
  toe = x:
    let
      k1 = 0.206;
      k2 = 3.0e-2;
      k3 = (1 + k1) / (1 + k2);
    in (0.5 * (k3 * x - k1 + sqrt ((pow (k3 * x - k1) 2) + 4 * k2 * k3 * x)));

  toeInv = x:
    let
      k1 = 0.206;
      k2 = 3.0e-2;
      k3 = (1 + k1) / (1 + k2);
    in (((pow x 2) + k1 * x) / (k3 * (x + k2)));

  computeMaxSaturation = a: b:
    let
      k0 = if (-1.88170328 * a - 0.80936493 * b) > 1 then
        1.19086277
      else if (1.81444104 * a - 1.19445276 * b) > 1 then
        0.73956515
      else
        1.35733652;
      k1 = if (-1.88170328 * a - 0.80936493 * b) > 1 then
        1.76576728
      else if (1.81444104 * a - 1.19445276 * b) > 1 then
        (-0.45954404)
      else
        (-9.15799e-3);
      k2 = if (-1.88170328 * a - 0.80936493 * b) > 1 then
        0.59662641
      else if (1.81444104 * a - 1.19445276 * b) > 1 then
        8.285427e-2
      else
        (-1.1513021);
      S = k0 + k1 * a + k2 * b;
    in S;

  oklabToLinearSRGBRaw = { L, a, b, alpha ? 1.0 }:
    let
      l_ = L + 0.3963377774 * a + 0.2158037573 * b;
      m_ = L - 0.1055613458 * a - 6.38541728e-2 * b;
      s_ = L - 8.94841775e-2 * a - 1.291485548 * b;
      l = l_ * l_ * l_;
      m = m_ * m_ * m_;
      s = s_ * s_ * s_;
    in {
      r = 4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s;
      g = -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s;
      b = -4.1960863e-3 * l - 0.7034186147 * m + 1.707614701 * s;
      a = alpha;
    };

  findCusp = a: b:
    let
      S = computeMaxSaturation a b;
      rgb = oklabToLinearSRGBRaw { L = 1; a = S * a; b = S * b; alpha = 1.0; };
      L_cusp = cbrt (safeDiv 1.0 (max (max rgb.r rgb.g) rgb.b));
      C_cusp_raw = L_cusp * S;
      C_cusp = abs C_cusp_raw;
    in {
      L = L_cusp;
      C = C_cusp;
    };

  getSTMax = a: b:
    let cusp = findCusp a b;
    in {
      S = safeDiv cusp.C cusp.L;
      T = safeDiv cusp.C (1 - cusp.L);
    };

  # oklab.nix (updated getCs)
  getCs = L: a: b:
    let
      cusp = findCusp a b;
      STMax = getSTMax a b;
      k = 1;
      STMid = {
        S = 0.11516993;
        T = 0.11239642;
      };
      C_mid = if L == 0 || L == 1 then
        0
      else
        0.9 * k * sqrt
        (sqrt (1 / (1 / pow (L * STMid.S) 4 + 1 / pow ((1 - L) * STMid.T) 4)));
      C_0 = if L == 0 || L == 1 then
        0
      else
        sqrt (1 / (1 / pow (L * 0.4) 2 + 1 / pow ((1 - L) * 0.8) 2));
    in {
      C_0 = C_0;
      C_mid = C_mid;
      C_max = cusp.C;
    };

}

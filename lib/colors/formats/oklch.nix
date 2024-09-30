# formats/oklch.nix
{ math, utils }:
{

  rgbToOklch = { r, g, b, a ? 1 }@rgb: let
    l = math.cbrt (0.4122214708 * rgb.r + 0.5363325363 * rgb.g + 0.0514459929 * rgb.b);
    m = math.cbrt (0.2119034982 * rgb.r + 0.6806995451 * rgb.g + 0.1073969566 * rgb.b);
  	s = math.cbrt (0.0883024619 * rgb.r + 0.2817188376 * rgb.g + 0.6299787005 * rgb.b);
    L = 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s;
    a = 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s;
    b = 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s;
  in {
    inherit L;
    C = math.sqrt ((math.pow a 2) + (math.pow b 2));
    h = math.atan2 b a;
  };


  oklchToRgb = { L, C, h, a ? 1 }@lch: let
    a = lch.C * math.cos lch.h;
    b = lch.C * math.sin lch.h;
    l = math.pow (lch.L + 0.3963377774 * a + 0.2158037573 * b) 3;
    m = math.pow (lch.L - 0.1055613458 * a - 0.0638541728 * b) 3;
    s = math.pow (lch.L - 0.0894841775 * a - 1.2914855480 * b) 3;
    rgb  = {
      r = 4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s;
      g = (-1.2684380046) * l + 2.6097574011 * m - 0.3413193965 * s;
      b = (-0.0041960863) * l - 0.7034186147 * m + 1.7076147010 * s;
    };
  in
    rgb;


  oklabToOklch = { L, a, b, alpha ? 1 }: let
    C = math.sqrt (a * a + b * b);
    h = math.atan2 b a;
    # Ensure h is in the range [0, tau)
    h' = if h < 0 then h + math.tau else h;
  in {
    inherit L C;
    h = h';
    alpha = alpha;
  };

  oklchToOklab = { L, C, h, alpha ? 1 }: {
    inherit L;
    a = C * math.cos h;
    b = C * math.sin h;
    alpha = alpha;
  };
}

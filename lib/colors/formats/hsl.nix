# formats/hsl.nix
{ math, lib, types }:

{
  rgbToHsl = rgb@{ r, g, b, a ? 1.0, meta ? {} }:
  let
    max = lib.max r (lib.max g b);
    min = lib.min r (lib.min g b);
    d = max - min;
    l = (max + min) / 2;
    s = if d == 0 then 0 else d / (if l < 0.5 then l * 2 else 2 - l * 2);
    h = (if d == 0 then 0 else
      if max == r then (g - b) / d + (if g < b then 6 else 0) else
      if max == g then (b - r) / d + 2 else (r - g) / d + 4) * 60;
  in types.HSL.check {
    h = math.mod h 360 / 360.0;
    inherit s l a;
  };

hslToRgb = hsl@{ h, s, l, a ? 1.0, meta ? {} }:
  let
    h' = h * 6;
    c = (1 - math.abs (2 * l - 1)) * s;
    x = c * (1 - math.abs (math.mod h' 2 - 1));
    m = l - c / 2;
    rgb' = builtins.elemAt [
      { r = c; g = x; b = 0; }
      { r = x; g = c; b = 0; }
      { r = 0; g = c; b = x; }
      { r = 0; g = x; b = c; }
      { r = x; g = 0; b = c; }
      { r = c; g = 0; b = x; }
    ] (builtins.floor h');
  in types.sRGB.check ({
    r = rgb'.r + m;
    g = rgb'.g + m;
    b = rgb'.b + m;
    inherit a;
  } // (if meta != {} then { inherit meta; } else {}));
}

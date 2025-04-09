# This file is now a function that accepts color-lib and lib
{ color-lib, lib }:

let
  inherit (color-lib) hexToRgb rgbToHex srgb_to_okhsl okhsl_to_srgb;
  inherit (lib.math) abs fmod; # For hue interpolation

  # Color Mixing function using Okhsl
  mixColors = color1: color2: ratio:
    let
      rgb1 = hexToRgb color1;
      rgb2 = hexToRgb color2;

      okhsl1 = srgb_to_okhsl { r = rgb1.r; g = rgb1.g; b = rgb1.b; };
      okhsl2 = srgb_to_okhsl { r = rgb2.r; g = rgb2.g; b = rgb2.b; };

      # Interpolate Alpha
      alpha = rgb1.alpha * (1.0 - ratio) + rgb2.alpha * ratio;

      # Interpolate Lightness and Saturation
      l = okhsl1.l * (1.0 - ratio) + okhsl2.l * ratio;
      s = okhsl1.s * (1.0 - ratio) + okhsl2.s * ratio;

      # Interpolate Hue (handle wrap-around)
      h1 = okhsl1.h;
      h2 = okhsl2.h;
      diff = h2 - h1;
      dist = abs diff;

      # Adjust hues for shortest path interpolation if distance > 0.5
      h1_adj = if dist > 0.5 && diff > 0.0 then h1 + 1.0 else h1;
      h2_adj = if dist > 0.5 && diff < 0.0 then h2 + 1.0 else h2;

      # Interpolate adjusted hues and wrap result
      h_interpolated = h1_adj * (1.0 - ratio) + h2_adj * ratio;
      h = fmod h_interpolated 1.0;

      # Convert back
      mixed_okhsl = { inherit h s l; };
      mixed_rgb_only = okhsl_to_srgb mixed_okhsl;
      mixed_rgb_alpha = mixed_rgb_only // { inherit alpha; };

    in rgbToHex mixed_rgb_alpha;

in {
  # Original Colors
  primary =   "#59C2FF";
  secondary = "#FF8F40";

  neutral = "#CED4DA";

  accent1 = "#B8CC52";
  accent2 = "#D2A6FF";

  base00 = "#263238";
  base01 = "#2E3C43";
  base02 = "#314549";
  base03 = "#546E7A";
  base04 = "#B2CCD6";
  base05 = "#DEEEFF";
  base06 = "#EEFFFF";
  base07 = "#FAFAFF";
  base08 = "#F07178";
  base09 = "#F78C6C";
  base0A = "#FFCB6B";
  base0B = "#C3E88D";
  base0C = "#89DDFF";
  base0D = "#82AAFF";
  base0E = "#C792EA";
  base0F = "#FF5370";

  # Expose the mixing function
  inherit mixColors;
}


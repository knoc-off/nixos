{ color-lib, lib, math }:
let
  inherit (color-lib)
    mixColors setOkhslLightness setOkhslSaturation adjustOkhslHue
    getOkhslLightness getOkhslSaturation setOkhslHue; # Added getOkhslSaturation, setOkhslHue

  # Define anchor background and foreground
  bg = color-lib.setOkhslLightness 0.15 "#263238"; # Dark Background
  fg = "#FAFAFF"; # Light Foreground

  # Define neutral based on bg/fg mix or a fixed value
  neutral = mixColors bg fg 0.5; # Or keep "#CED4DA";


  # --- Generate Accent Colors (base08-base0F) ---
  accentL = 0.5; # Target lightness for accents
  accentS = 0.5; # Target saturation for accents

  # Generate 8 evenly spaced hue values (0.0 to 0.875) using arange
  numHues = 8;
  hueStep = 1.0 / numHues;
  # math.arange generates `floor((max - min) / step)` elements.
  # So arange 0.0 1.0 step generates floor(1.0 / step) = floor(numHues) = numHues elements.
  accentHues = math.arange 0.0 1.0 hueStep; # Generates [0.0, 0.125, ..., 0.875]


  # --- Generate Grayscale (base00-base07) ---
  # Generate 8 evenly spaced lightness values from bg lightness to fg lightness
  l_bg = getOkhslLightness bg;
  l_fg = getOkhslLightness fg;
  grayLightnesses = lib.lists.genList (n: l_bg + n * (l_fg - l_bg) / 7) 8;

  # Generate 8 evenly spaced mixing proportions from 0.0 (bg) to 1.0 (fg)
  mixProportions = lib.lists.genList (n: n * 1.0 / 7) 8;

  # Generate base colors by mixing bg and fg according to proportions,
  # then setting the corresponding lightness.
  baseColors = lib.lists.genList (n:
    let
      prop = builtins.elemAt mixProportions n;
      light = builtins.elemAt grayLightnesses n;
      mixedColor = mixColors bg fg prop;
      # Slightly reduce saturation
      desaturatedColor = setOkhslSaturation 0.25 mixedColor;
    in
      # Set the target lightness on the desaturated color
      setOkhslLightness light desaturatedColor
  ) 8;

  # Assign generated colors to base00-base07
  base00 = builtins.elemAt baseColors 0; # Darkest Background
  base01 = builtins.elemAt baseColors 1;
  base02 = builtins.elemAt baseColors 2;
  base03 = builtins.elemAt baseColors 3; # Comments, low-contrast foreground
  base04 = builtins.elemAt baseColors 4; # Default Foreground secondary
  base05 = builtins.elemAt baseColors 5; # Default Foreground primary
  base06 = builtins.elemAt baseColors 6;
  base07 = builtins.elemAt baseColors 7; # Lightest Foreground




  # Helper function to create an accent color with a specific numeric hue
  # Takes a base color, target L, target S, and the target numeric Hue (0.0-1.0)
  createAccent = baseColor: targetL: targetS: targetHue:
    let
      modifiedL = setOkhslLightness targetL baseColor;
      modifiedLS = setOkhslSaturation targetS modifiedL;
      finalColor = setOkhslHue targetHue modifiedLS;
    in finalColor;

  # Use the helper and the generated numeric hues for base08-base0F
  # We use 'neutral' as the starting point, its original L/S/H don't matter.
  base08 = createAccent neutral accentL accentS (builtins.elemAt accentHues 0); # Hue 0.0   (Red)
  base09 = createAccent neutral accentL accentS (builtins.elemAt accentHues 1); # Hue 0.125 (Orange)
  base0A = createAccent neutral accentL accentS (builtins.elemAt accentHues 2); # Hue 0.25  (Yellow)
  base0B = createAccent neutral accentL accentS (builtins.elemAt accentHues 3); # Hue 0.375 (Green)
  base0C = createAccent neutral accentL accentS (builtins.elemAt accentHues 4); # Hue 0.5   (Cyan)
  base0D = createAccent neutral accentL accentS (builtins.elemAt accentHues 5); # Hue 0.625 (Blue)
  base0E = createAccent neutral accentL accentS (builtins.elemAt accentHues 6); # Hue 0.75  (Magenta)
  base0F = createAccent neutral accentL accentS (builtins.elemAt accentHues 7); # Hue 0.875 (Violet)

  # --- Determine Theme Type ---
  bgLightness = getOkhslLightness bg;
  themeType = if bgLightness < 0.5 then "dark" else "light";

in {
  #type = themeType;

  # Expose Generated Base16 Palette (removing '#' prefix)
  base00 = lib.removePrefix "#" base00; # theme.base00
  base01 = lib.removePrefix "#" base01; # theme.base01
  base02 = lib.removePrefix "#" base02; # theme.base02
  base03 = lib.removePrefix "#" base03; # theme.base03
  base04 = lib.removePrefix "#" base04; # theme.base04
  base05 = lib.removePrefix "#" base05; # theme.base05
  base06 = lib.removePrefix "#" base06; # theme.base06
  base07 = lib.removePrefix "#" base07; # theme.base07
  base08 = lib.removePrefix "#" base08; # theme.base08
  base09 = lib.removePrefix "#" base09; # theme.base09
  base0A = lib.removePrefix "#" base0A; # theme.base0A
  base0B = lib.removePrefix "#" base0B; # theme.base0B
  base0C = lib.removePrefix "#" base0C; # theme.base0C
  base0D = lib.removePrefix "#" base0D; # theme.base0D
  base0E = lib.removePrefix "#" base0E; # theme.base0E
  base0F = lib.removePrefix "#" base0F; # theme.base0F
}

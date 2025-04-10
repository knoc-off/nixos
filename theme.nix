{ color-lib, lib, math }:
let
  inherit (color-lib)
    mixColors setOkhslLightness setOkhslSaturation adjustOkhslHue
    getOkhslLightness setOkhslHue; # Added setOkhslHue

  # Define anchor background and foreground
  bg = color-lib.setOkhslLightness 0.15 "#263238"; # Dark Background
  fg = "#FAFAFF"; # Light Foreground

  # Define neutral based on bg/fg mix or a fixed value
  neutral = mixColors bg fg 0.5; # Or keep "#CED4DA";

  # --- Generate Grayscale (base00-base07) ---
  # Adjust lightness values for desired contrast steps
  base00 = bg; # Darkest Background
  base01 = setOkhslLightness 0.28 bg; # Dark Background highlight
  base02 = setOkhslLightness 0.32 bg; # Dark Selection Background
  base03 = setOkhslLightness 0.45 bg; # Comments, low-contrast foreground
  base04 = setOkhslLightness 0.70 fg; # Default Foreground secondary
  base05 = setOkhslLightness 0.80 fg; # Default Foreground primary
  base06 = setOkhslLightness 0.90 fg; # Light Background highlight
  base07 = fg; # Lightest Foreground

  # --- Define Hues for Core Palette ---
  # Keep these for defining primary/secondary etc. if needed, or replace their usage below.
  coreHueBlue =    "#59C2FF";
  coreHueOrange =  "#F8961E";
  coreHueGreen =   "#90BE6D";
  coreHueMagenta = "#C792EA";

  # --- Core Palette ---
  primary = coreHueBlue; # Blue
  secondary = coreHueOrange; # Orange
  accent1 = coreHueGreen; # Green
  accent2 = coreHueMagenta; # Light Purple

  # --- Generate Accent Colors (base08-base0F) ---
  accentL = 0.7; # Target lightness for accents
  accentS = 0.7; # Target saturation for accents

  # Generate 8 evenly spaced hue values (0.0 to 0.875) using arange
  numHues = 8;
  hueStep = 1.0 / numHues;
  # math.arange generates `floor((max - min) / step)` elements.
  # So arange 0.0 1.0 step generates floor(1.0 / step) = floor(numHues) = numHues elements.
  accentHues = math.arange 0.0 1.0 hueStep; # Generates [0.0, 0.125, ..., 0.875]

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

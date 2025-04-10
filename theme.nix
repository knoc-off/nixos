{ color-lib, lib, math }:
let
  inherit (color-lib)
    mixColors setOkhslLightness setOkhslSaturation adjustOkhslHue
    getOkhslLightness; # Added getOkhslLightness

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

  hueRed =     "#F94144"; # Original base0F
  hueOrange =  "#F8961E"; # "#FF8F40"
  hueYellow =  "#F9C74F"; # Original base0A
  hueGreen =   "#90BE6D"; # "#B8CC52"
  hueCyan =    "#4D908E"; # Adjusted Cyan - More distinct from Blue
  hueBlue =    "#59C2FF"; # "#59C2FF"
  hueMagenta = "#C792EA"; # Original base0E
  hueViolet =  "#ec0868"; # Original base08 (using as Violet/Alt Red)

  # --- Core Palette ---
  primary = hueBlue; # Blue
  secondary = hueOrange; # Orange
  accent1 = hueGreen; # Green
  accent2 = hueMagenta; # Light Purple

  # --- Generate Accent Colors (base08-base0F) ---
  # Set consistent lightness and saturation for accents
  setAccent = l: s: hex: setOkhslSaturation s (setOkhslLightness l hex);
  accentL = 0.7; # Target lightness for accents
  accentS = 0.7; # Target saturation for accents

  base08 = setAccent accentL accentS hueRed;      # Red
  base09 = setAccent accentL accentS hueOrange;   # Orange
  base0A = setAccent accentL accentS hueYellow;   # Yellow
  base0B = setAccent accentL accentS hueGreen;    # Green
  base0C = setAccent accentL accentS hueCyan;     # Cyan
  base0D = setAccent accentL accentS hueBlue;     # Blue
  base0E = setAccent accentL accentS hueMagenta;  # Magenta
  base0F = setAccent accentL accentS hueViolet;   # Violet

  # --- Determine Theme Type ---
  bgLightness = getOkhslLightness bg;
  themeType = if bgLightness < 0.5 then "dark" else "light";

in {
  # Expose Core Palette (removing '#' prefix)
  primary = lib.removePrefix "#" primary; # theme.primary
  secondary = lib.removePrefix "#" secondary; # theme.secondary
  neutral = lib.removePrefix "#" neutral; # theme.neutral
  accent1 = lib.removePrefix "#" accent1; # theme.accent1
  accent2 = lib.removePrefix "#" accent2; # theme.accent2

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

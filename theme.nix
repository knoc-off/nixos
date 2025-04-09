# This file is now a function that accepts color-lib and lib
{ color-lib, lib }:

let
  inherit (color-lib) mixColors setOkhslLightness setOkhslSaturation adjustOkhslHue;

  # --- Core Palette ---
  primary =   "#59C2FF"; # Blue
  secondary = "#FF8F40"; # Orange
  accent1 =   "#B8CC52"; # Green
  accent2 =   "#D2A6FF"; # Light Purple/Accent Magenta

  # Define anchor background and foreground
  bg = "#263238"; # Dark Background
  fg = "#FAFAFF"; # Light Foreground

  # Define neutral based on bg/fg mix or a fixed value
  neutral = mixColors bg fg 0.5; # Or keep "#CED4DA";

  # --- Generate Grayscale (base00-base07) ---
  # Adjust lightness values for desired contrast steps
  base00 = bg;                             # Darkest Background
  base01 = setOkhslLightness 0.28 bg;      # Dark Background highlight
  base02 = setOkhslLightness 0.32 bg;      # Dark Selection Background
  base03 = setOkhslLightness 0.45 bg;      # Comments, low-contrast foreground
  base04 = setOkhslLightness 0.80 fg;      # Default Foreground secondary
  base05 = setOkhslLightness 0.92 fg;      # Default Foreground primary
  base06 = setOkhslLightness 0.97 fg;      # Light Background highlight
  base07 = fg;                             # Lightest Foreground

  # --- Define Base Hues for Accents (base08-base0F) ---
  # Using existing colors as hue sources
  hueRed     = "#FF5370"; # Original base0F
  hueOrange  = secondary; # "#FF8F40"
  hueYellow  = "#FFCB6B"; # Original base0A
  hueGreen   = accent1;   # "#B8CC52"
  hueCyan    = "#89DDFF"; # Original base0C
  hueBlue    = primary;   # "#59C2FF"
  hueMagenta = "#C792EA"; # Original base0E
  hueViolet  = "#F07178"; # Original base08 (using as Violet/Alt Red)

  # --- Generate Accent Colors (base08-base0F) ---
  # Set consistent lightness and saturation for accents
  # Adjust these values (e.g., l=0.7, s=0.8) to taste
  setAccent = l: s: hex: setOkhslSaturation s (setOkhslLightness l hex);
  accentL = 0.70; # Target lightness for accents
  accentS = 0.85; # Target saturation for accents

  base08 = setAccent accentL accentS hueRed;     # Red
  base09 = setAccent accentL accentS hueOrange;  # Orange
  base0A = setAccent accentL accentS hueYellow;  # Yellow
  base0B = setAccent accentL accentS hueGreen;   # Green
  base0C = setAccent accentL accentS hueCyan;    # Cyan
  base0D = setAccent accentL accentS hueBlue;    # Blue
  base0E = setAccent accentL accentS hueMagenta; # Magenta
  base0F = setAccent accentL accentS hueViolet;  # Violet / Alt Red

in {
  # Expose Core Palette
  inherit primary secondary neutral accent1 accent2;

  # Expose Generated Base16 Palette
  inherit base00 base01 base02 base03 base04 base05 base06 base07;
  inherit base08 base09 base0A base0B base0C base0D base0E base0F;

  # Expose the mixing function
  inherit mixColors;
}


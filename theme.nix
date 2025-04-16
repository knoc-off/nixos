{ lib, math, color-lib }:

let
  # Import necessary functions from the provided libraries
  inherit (lib) genList elemAt removePrefix;
  inherit (math) arange; # Assuming math.nix provides arange
  inherit (color-lib)
    # Core manipulation functions
    setOkhslLightness
    setOkhslSaturation
    setOkhslHue
    getOkhslLightness
    mixColors;
  # Potentially useful, but maybe not needed for this specific approach:
  # getOkhslSaturation getOkhslHue adjustOkhslHue adjustOkhslLightness etc.

  # --- Theme Anchors ---
  # Define the darkest background and lightest foreground hex codes.
  # These anchor the entire grayscale ramp.
  bg = "#263238"; # Dark Blue-Gray
  fg = "#ECEFF1"; # Light Gray

  # --- Neutral Tone ---
  # A mid-tone used for subtle mixing to increase cohesion across colors.
  # Derived by mixing the background and foreground.
  neutral = mixColors bg fg 0.5; # Mix halfway between bg and fg

  # --- Grayscale Generation (base00-base07) ---
  # Generate 8 perceptually uniform lightness steps between bg and fg.
  l_bg = getOkhslLightness bg;
  l_fg = getOkhslLightness fg;
  numGrays = 8;

  # Generate target lightness values from l_bg to l_fg
  grayLightnesses =
    genList (n: l_bg + n * (l_fg - l_bg) / (numGrays - 1)) numGrays;

  # Create the grayscale palette:
  # We will generate each gray step by setting the calculated lightness
  # directly onto the background color 'bg'. This preserves the hue of 'bg'.
  # Then, we mix slightly with 'neutral' for overall theme harmony.
  baseColors = genList (n:
    let
      targetLightness = elemAt grayLightnesses n;
      # Set the lightness on the original background color

      mixRatio = 0.1;
      mixed = mixColors bg neutral mixRatio;
    in
      setOkhslLightness targetLightness mixed
  ) numGrays;

  # Assign generated grays to base00-base07 following Base16 convention
  # (base00 = darkest, base07 = lightest)
  base00 = elemAt baseColors 0; # Darkest Background
  base01 = elemAt baseColors 1; # Lighter Background (UI)
  base02 = elemAt baseColors 2; # Selection Background
  base03 = elemAt baseColors 3; # Comments, Low-contrast Fg
  base04 = elemAt baseColors 4; # Default Foreground (secondary)
  base05 = elemAt baseColors 5; # Default Foreground (primary)
  base06 = elemAt baseColors 6; # Light Foreground (UI)
  base07 = elemAt baseColors 7; # Lightest Foreground

  # --- Accent Color Generation (base08-base0F) ---
  # Define target perceptual lightness and saturation for accents.
  # Adjust these for desired vibrancy and contrast.
  accentL = 0.70; # Target lightness (perceptual) - adjust as needed
  accentS = 0.65; # Target saturation (perceptual) - adjust as needed

  # Generate 8 evenly spaced hues in Okhsl (0.0 to 1.0 scale)
  numHues = 8;
  hueStep = 1.0 / numHues;
  # Generates [0.0, 0.125, 0.25, 0.375, 0.5, 0.625, 0.75, 0.875]
  accentHues = arange 0.0 1.0 hueStep;

  # Helper function to create an accent color.
  # Starts from the neutral base, sets the target L/S, applies the specific hue,
  # and mixes with the theme's neutral color for cohesion.
  createAccent = targetHue:
    let
      # Start with neutral, set target Lightness and Saturation
      baseAccent = setOkhslSaturation accentS (setOkhslLightness accentL neutral);
      # Apply the specific hue
      hueSetColor = setOkhslHue targetHue baseAccent;
      # Mix slightly with neutral for overall theme harmony (consistent mix ratio)
      mixRatio = 0.1;
    in
      mixColors hueSetColor neutral mixRatio;

  # Generate the 8 accent colors using the standard Base16 hue order (approx)
  # Red, Orange, Yellow, Green, Cyan, Blue, Magenta, Violet/Brown/etc.
  base08 = createAccent (elemAt accentHues 0); # Red
  base09 = createAccent (elemAt accentHues 1); # Orange
  base0A = createAccent (elemAt accentHues 2); # Yellow
  base0B = createAccent (elemAt accentHues 3); # Green
  base0C = createAccent (elemAt accentHues 4); # Cyan
  base0D = createAccent (elemAt accentHues 5); # Blue
  base0E = createAccent (elemAt accentHues 6); # Magenta
  base0F = createAccent (elemAt accentHues 7); # Violet/Brown

  # --- Determine Theme Type (Optional Metadata) ---
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


{ lib, math, color-lib, ... }:
let
  # Import necessary functions from the provided libraries
  inherit (lib) elemAt removePrefix;
  inherit (lib.lists) genList imap0 map;
  inherit (math) cubicBezier linearInterpolatePoints; # Use linear interpolation for grays
  inherit (color-lib)
    # Core manipulation functions
    setOkhslLightness
    setOkhslSaturation
    setOkhslHue
    getOkhslLightness
    mixColors;
  # Potentially useful, but maybe not needed for this specific approach:
  # getOkhslSaturation getOkhslHue adjustOkhslHue adjustOkhslLightness etc.

  # --- Hue Offset ---
  # Define an offset for the accent hues (0.0 to 1.0, wraps around)
  hueOffset = 0.08; # Default: 0.0 (no offset)

  # --- Theme Generator Function ---
  # Generates a complete theme palette given background/foreground colors and parameters
  mkTheme = { bg, fg, accentL, accentS }: let

    # --- Neutral Tone ---
    # A mid-tone used for subtle mixing to increase cohesion across colors.
    # Derived by mixing the background and foreground.
    neutral = mixColors bg fg 0.5; # Mix halfway between bg and fg

    # --- Grayscale Generation (base00-base07) ---
    # Generate 8 lightness steps between bg and fg using a custom interpolation curve.
    l_bg = getOkhslLightness bg;
    l_fg = getOkhslLightness fg;
    numGrays = 8;

    # Define the range around the midpoint (0.5) for the lightness interpolation.
    # A value of 0.2 means the lightness will be 0.5 - 0.2 = 0.3 just before the midpoint
    # and 0.5 + 0.2 = 0.7 just after the midpoint.
    midpointLightnessRange = 0.15;

    # Define the points for the custom lightness interpolation curve
    # Creates a slow rise, a defined midpoint, and then a faster rise.
    lightnessInterpolationPoints = [
      [ 0.0 0.0 ] # Start at t=0, factor=0
      [ 0.5 (0.5 - midpointLightnessRange) ] # Point just before midpoint
      [ 0.6 (0.5 + midpointLightnessRange) ] # Point just after midpoint
      [ 1.0 1.0 ] # End at t=1, factor=1
    ];

    # Create the grayscale palette:
    # Generate t values from 0.0 to 1.0 for the interpolation function input.
    # Iterate through the t values using index-aware map.
    # For each step, calculate the target lightness using the Bézier curve.
    # Calculate the corresponding color mix between bg and fg based on t.
    # Set the calculated target lightness on the mixed color.
    # Mix slightly with 'neutral' for overall theme harmony.
    baseColors = imap0 (n: _: # n = index (0-7), _ = ignored element from genList
      let
        # Generate t value (interpolation factor) from 0.0 to 1.0
        t = n * 1.0 / (numGrays - 1);

        # Calculate target lightness factor using linear interpolation between defined points
        # Output is 0.0 to 1.0, following the custom curve
        lightnessFactor = linearInterpolatePoints lightnessInterpolationPoints t;
        # Scale the factor to the [l_bg, l_fg] range
        targetLightness = l_bg + lightnessFactor * (l_fg - l_bg);

        # Interpolate base color between bg and fg using the same t (linear mix)
        interpolatedColor = mixColors bg fg t;

        # Mix with neutral for cohesion
        neutralMixRatio = 0.1;
        neutralMixedColor = mixColors interpolatedColor neutral neutralMixRatio;

        # Set the target lightness calculated by the linear interpolation curve
        finalColor = setOkhslLightness targetLightness neutralMixedColor;
      in
        finalColor
    ) (genList (x: x) numGrays); # Generate a list [0, 1, ..., numGrays-1] to map over

    # Assign generated grays to base00-base07 following Base16 convention
    # (base00 = darkest, base07 = lightest)
    base00 = elemAt baseColors 0; # Default Background
    base01 = elemAt baseColors 1; # Lighter Background (e.g., UI elements)
    base02 = elemAt baseColors 2; # Selection Background
    base03 = elemAt baseColors 3; # Comments, Invisibles, Line Highlighting
    base04 = elemAt baseColors 4; # Dark Foreground (Used for status bars)
    base05 = elemAt baseColors 5; # Default Foreground (Used for text)
    base06 = elemAt baseColors 6; # Light Foreground (Not often used)
    base07 = elemAt baseColors 7; # Light Background (e.g., UI elements)

    # --- Accent Color Generation (base08-base0F) ---
    numHues = 9; # We do 9 because we dont want it to wrap fully

    # Helper for float modulo 1.0 (wraps hue values)
    mod1 = x: x - builtins.floor x;

    # Generate accent hues using the accent Bézier curve and apply offset
    offsetAccentHues = imap0 (n: _: # n = index (0-7)
      let
        # Generate t value (interpolation factor) from 0.0 to 1.0
        t = n * 1.0 / (numHues - 1);
        # Calculate base hue factor using the custom cubic-bezier
        # We up the number of warm colors
        #baseHueFactor = cubicBezier 0.34 0.07 0.37 0.43 t;
        baseHueFactor = cubicBezier 0.38 0.11 0.37 0.43 t;
        # Apply offset and wrap using mod1
        offsetHue = mod1 (baseHueFactor + hueOffset);
      in
        offsetHue
    ) (genList (x: x) numHues); # Generate list [0, 1, ..., numHues-1]

    # Helper function to create an accent color.
    # Starts from the neutral base, sets the target L/S, applies the specific hue,
    # and mixes with the theme's neutral color for cohesion.
    createAccent = targetHue:
      let
        # Start with neutral, set target Lightness and Saturation
        baseAccent = setOkhslSaturation accentS neutral;
        # Apply the specific hue
        hueSetColor = setOkhslHue targetHue baseAccent;
        # Mix slightly with neutral for overall theme harmony (consistent mix ratio)
        mixRatio = 0.1;
        neutralMixedColor = mixColors hueSetColor neutral mixRatio;
      in
        setOkhslLightness accentL neutralMixedColor;

    # Generate the 8 accent colors using the offset hues
    # The perceived color (Red, Orange, etc.) will depend on the hueOffset.
    base08 = createAccent (elemAt offsetAccentHues 0); # Accent 1
    base09 = createAccent (elemAt offsetAccentHues 1); # Accent 2
    base0A = createAccent (elemAt offsetAccentHues 2); # Accent 3
    base0B = createAccent (elemAt offsetAccentHues 3); # Accent 4
    base0C = createAccent (elemAt offsetAccentHues 4); # Accent 5
    base0D = createAccent (elemAt offsetAccentHues 5); # Accent 6
    base0E = createAccent (elemAt offsetAccentHues 6); # Accent 7
    base0F = createAccent (elemAt offsetAccentHues 7); # Accent 8

    # --- Determine Theme Type (Optional Metadata) ---
    bgLightness = getOkhslLightness bg;
    themeType = if bgLightness < 0.5 then "dark" else "light";

  in {
    #type = themeType;

    # Expose Generated Base16 Palette (removing '#' prefix)
    base00 = lib.removePrefix "#" base00; # theme.dark.base00 # Default Background
    base01 = lib.removePrefix "#" base01; # theme.dark.base01 # Lighter Background (e.g., UI elements)
    base02 = lib.removePrefix "#" base02; # theme.dark.base02 # Selection Background
    base03 = lib.removePrefix "#" base03; # theme.dark.base03 # Comments, Invisibles, Line Highlighting
    base04 = lib.removePrefix "#" base04; # theme.dark.base04 # Dark Foreground (Used for status bars)
    base05 = lib.removePrefix "#" base05; # theme.dark.base05 # Default Foreground (Used for text)
    base06 = lib.removePrefix "#" base06; # theme.dark.base06 # Light Foreground (Not often used)
    base07 = lib.removePrefix "#" base07; # theme.dark.base07 # Light Background (e.g., UI elements)
    base08 = lib.removePrefix "#" base08; # theme.dark.base08 # Red
    base09 = lib.removePrefix "#" base09; # theme.dark.base09 # Orange
    base0A = lib.removePrefix "#" base0A; # theme.dark.base0A # Yellow
    base0B = lib.removePrefix "#" base0B; # theme.dark.base0B # green
    base0C = lib.removePrefix "#" base0C; # theme.dark.base0C # Blue
    base0D = lib.removePrefix "#" base0D; # theme.dark.base0D # cyan
    base0E = lib.removePrefix "#" base0E; # theme.dark.base0E # purple
    base0F = lib.removePrefix "#" base0F; # theme.dark.base0F # violet
  };

in {
  # Dark theme: Dark background, light foreground
  dark = mkTheme {
    bg = "#1b2429"; # Dark Blue-Gray
    fg = "#ECEFF1"; # Light Gray
    accentL = 0.6; # Target lightness for dark mode
    accentS = 0.97; # Target saturation
  };

  # Light theme: Light background, dark foreground
  light = mkTheme {
    bg = "#ECEFF1"; # Light Gray
    fg = "#1b2429"; # Dark Blue-Gray
    accentL = 0.55; # Slightly darker accents for better contrast on light background
    accentS = 0.85; # Slightly less saturated for light mode
  };
}


{ lib ? import <nixpkgs/lib>, math ? import ../math.nix { inherit lib; }, colorMath ? import ./color-math.nix { inherit lib math; } }:

let
  inherit (math) clamp hexToDec;
  inherit (colorMath) srgb_to_okhsl okhsl_to_srgb srgb_to_okhsv okhsv_to_srgb;
  epsilon = 1.0e-8;

  # --- Hex <-> RGB Conversion ---

  # Converts a hex color string (e.g., "#RRGGBB" or "RRGGBB") to an RGB attribute set { r, g, b } with values 0.0-1.0
  hexToRgb = hex:
    let
      hex' = builtins.replaceStrings [ "#" ] [ "" ] hex;
      r_hex = builtins.substring 0 2 hex';
      g_hex = builtins.substring 2 2 hex';
      b_hex = builtins.substring 4 2 hex';
      r_int = hexToDec r_hex;
      g_int = hexToDec g_hex;
      b_int = hexToDec b_hex;
    in {
      r = r_int / 255.0;
      g = g_int / 255.0;
      b = b_int / 255.0;
    };

  # Converts an RGB attribute set { r, g, b } (values 0.0-1.0) to a hex color string "#RRGGBB"
  rgbToHex = rgb:
    let
      toHexByte = val:
        let
          byte = builtins.floor (clamp val 0.0 1.0 * 255.0 + 0.5); # Add 0.5 for rounding
          hexChars = "0123456789ABCDEF";
          highNibble = builtins.substring (byte / 16) 1 hexChars;
          lowNibble = builtins.substring (math.mod byte 16) 1 hexChars;
        in highNibble + lowNibble;
      r_hex = toHexByte rgb.r;
      g_hex = toHexByte rgb.g;
      b_hex = toHexByte rgb.b;
    in "#${r_hex}${g_hex}${b_hex}";

  # --- Color Manipulation Functions ---

  # Generic function to modify a component of a color model
  modifyComponent = modelConversionFunc: inverseModelConversionFunc: componentName: modifierFunc: hexColor:
    let
      rgb = hexToRgb hexColor;
      modelColor = modelConversionFunc rgb;
      modifiedValue = modifierFunc modelColor.${componentName};
      modifiedModelColor = modelColor // { ${componentName} = modifiedValue; }; # Update the specific component
      modifiedRgb = inverseModelConversionFunc modifiedModelColor;
    in rgbToHex modifiedRgb;

  # --- Okhsl Manipulation ---

  # Modify Okhsl Lightness (l)
  # modifierFunc: a function that takes the current lightness (0-1) and returns the new lightness
  modifyOkhslLightness = modifierFunc: hexColor:
    modifyComponent srgb_to_okhsl okhsl_to_srgb "l" modifierFunc hexColor;

  # Modify Okhsl Saturation (s)
  # modifierFunc: a function that takes the current saturation (0-1) and returns the new saturation
  modifyOkhslSaturation = modifierFunc: hexColor:
    modifyComponent srgb_to_okhsl okhsl_to_srgb "s" modifierFunc hexColor;

  # Modify Okhsl Hue (h)
  # modifierFunc: a function that takes the current hue (0-1) and returns the new hue (wraps around)
  modifyOkhslHue = modifierFunc: hexColor:
    let
      wrappedModifier = currentHue: math.fmod (modifierFunc currentHue) 1.0; # Ensure hue wraps
    in modifyComponent srgb_to_okhsl okhsl_to_srgb "h" wrappedModifier hexColor;

  # --- Okhsv Manipulation ---

  # Modify Okhsv Value (v)
  # modifierFunc: a function that takes the current value (0-1) and returns the new value
  modifyOkhsvValue = modifierFunc: hexColor:
    modifyComponent srgb_to_okhsv okhsv_to_srgb "v" modifierFunc hexColor;

  # Modify Okhsv Saturation (s)
  # modifierFunc: a function that takes the current saturation (0-1) and returns the new saturation
  modifyOkhsvSaturation = modifierFunc: hexColor:
    modifyComponent srgb_to_okhsv okhsv_to_srgb "s" modifierFunc hexColor;

  # Modify Okhsv Hue (h)
  # modifierFunc: a function that takes the current hue (0-1) and returns the new hue (wraps around)
  modifyOkhsvHue = modifierFunc: hexColor:
    let
      wrappedModifier = currentHue: math.fmod (modifierFunc currentHue) 1.0; # Ensure hue wraps
    in modifyComponent srgb_to_okhsv okhsv_to_srgb "h" wrappedModifier hexColor;

  # --- Convenience Functions ---

  # Set Okhsl Lightness to a specific value
  setOkhslLightness = newL: hexColor:
    modifyOkhslLightness ( _: newL ) hexColor;

  # Adjust Okhsl Lightness by an amount (e.g., adjustOkhslLightness 0.1 increases lightness by 0.1)
  adjustOkhslLightness = deltaL: hexColor:
    modifyOkhslLightness ( currentL: clamp (currentL + deltaL) 0.0 1.0 ) hexColor;

  # Scale Okhsl Lightness by a factor (e.g., scaleOkhslLightness 1.1 increases lightness by 10%)
  scaleOkhslLightness = factorL: hexColor:
    modifyOkhslLightness ( currentL: clamp (currentL * factorL) 0.0 1.0 ) hexColor;

  # Set Okhsl Saturation
  setOkhslSaturation = newS: hexColor:
    modifyOkhslSaturation ( _: newS ) hexColor;

  # Adjust Okhsl Saturation
  adjustOkhslSaturation = deltaS: hexColor:
    modifyOkhslSaturation ( currentS: clamp (currentS + deltaS) 0.0 1.0 ) hexColor;

  # Scale Okhsl Saturation
  scaleOkhslSaturation = factorS: hexColor:
    modifyOkhslSaturation ( currentS: clamp (currentS * factorS) 0.0 1.0 ) hexColor;

  # Set Okhsl Hue
  setOkhslHue = newH: hexColor:
    modifyOkhslHue ( _: newH ) hexColor;

  # Adjust Okhsl Hue (rotate hue)
  adjustOkhslHue = deltaH: hexColor:
    modifyOkhslHue ( currentH: currentH + deltaH ) hexColor; # Wrapping handled by modifyOkhslHue

  # Set Okhsv Value
  setOkhsvValue = newV: hexColor:
    modifyOkhsvValue ( _: newV ) hexColor;

  # Adjust Okhsv Value
  adjustOkhsvValue = deltaV: hexColor:
    modifyOkhsvValue ( currentV: clamp (currentV + deltaV) 0.0 1.0 ) hexColor;

  # Scale Okhsv Value
  scaleOkhsvValue = factorV: hexColor:
    modifyOkhsvValue ( currentV: clamp (currentV * factorV) 0.0 1.0 ) hexColor;

  # Set Okhsv Saturation
  setOkhsvSaturation = newS: hexColor:
    modifyOkhsvSaturation ( _: newS ) hexColor;

  # Adjust Okhsv Saturation
  adjustOkhsvSaturation = deltaS: hexColor:
    modifyOkhsvSaturation ( currentS: clamp (currentS + deltaS) 0.0 1.0 ) hexColor;

  # Scale Okhsv Saturation
  scaleOkhsvSaturation = factorS: hexColor:
    modifyOkhsvSaturation ( currentS: clamp (currentS * factorS) 0.0 1.0 ) hexColor;

  # Set Okhsv Hue
  setOkhsvHue = newH: hexColor:
    modifyOkhsvHue ( _: newH ) hexColor;

  # Adjust Okhsv Hue (rotate hue)
  adjustOkhsvHue = deltaH: hexColor:
    modifyOkhsvHue ( currentH: currentH + deltaH ) hexColor; # Wrapping handled by modifyOkhsvHue

in {
  # Export core conversion functions
  inherit hexToRgb rgbToHex;

  # Export Okhsl modification functions
  inherit modifyOkhslLightness modifyOkhslSaturation modifyOkhslHue;
  inherit setOkhslLightness adjustOkhslLightness scaleOkhslLightness;
  inherit setOkhslSaturation adjustOkhslSaturation scaleOkhslSaturation;
  inherit setOkhslHue adjustOkhslHue;

  # Export Okhsv modification functions
  inherit modifyOkhsvValue modifyOkhsvSaturation modifyOkhsvHue;
  inherit setOkhsvValue adjustOkhsvValue scaleOkhsvValue;
  inherit setOkhsvSaturation adjustOkhsvSaturation scaleOkhsvSaturation;
  inherit setOkhsvHue adjustOkhsvHue;
}

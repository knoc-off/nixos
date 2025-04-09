{ lib ? import <nixpkgs/lib>, math ? import ../math.nix { inherit lib; }, colorMath ? import ./color-math.nix { inherit lib math; } }:

let
  inherit (lib) stringToCharacters toUpper removePrefix stringLength elem all concatStrings substring map filter;
  inherit (math) clamp; # Removed hexToDec from math
  inherit (colorMath) srgb_to_okhsl okhsl_to_srgb srgb_to_okhsv okhsv_to_srgb;
  epsilon = 1.0e-8;

  # --- Hex Helpers (copied from color-tests.nix) ---

  hexDigitToDec = hexDigit:
    let
      hexChars = {
        "0" = 0; "1" = 1; "2" = 2; "3" = 3; "4" = 4; "5" = 5; "6" = 6; "7" = 7; "8" = 8; "9" = 9;
        "A" = 10; "B" = 11; "C" = 12; "D" = 13; "E" = 14; "F" = 15;
        "a" = 10; "b" = 11; "c" = 12; "d" = 13; "e" = 14; "f" = 15;
      };
    in if builtins.hasAttr hexDigit hexChars then
      hexChars.${hexDigit}
    else
      throw "Invalid hex digit: ${hexDigit}";

  hexToDec = hexStr:
    assert builtins.isString hexStr;
    let
      hexDigits = stringToCharacters hexStr;
      # Validate all digits are hex
      _ = map (d: assert hexDigitToDec d >= 0; true) hexDigits;
      hexToDecHelper = digits: acc:
        if digits == [ ] then acc
        else let
          digit = builtins.head digits;
          remainingDigits = builtins.tail digits;
          digitValue = hexDigitToDec digit;
        in hexToDecHelper remainingDigits (acc * 16 + digitValue);
    in if hexStr == "" then
      throw "Empty hex string"
    else
      hexToDecHelper hexDigits 0;

  isValidHex = str:
    let
      cleanHex = removePrefix "#" str;
      validChars = [ "0" "1" "2" "3" "4" "5" "6" "7" "8" "9" "A" "B" "C" "D" "E" "F" ];
      chars = stringToCharacters (toUpper cleanHex);
      validLengths = [ 3 4 6 8 ];
      isValidLength = elem (stringLength cleanHex) validLengths;
    in isValidLength && all (c: elem c validChars) chars;

  splitHex = hex:
    let
      cleanHex = removePrefix "#" hex;
      _ = if !(isValidHex cleanHex) then throw "Invalid hex color code: ${hex}" else true;
      normalizedHex = toUpper (
        if stringLength cleanHex == 3 then
          concatStrings (map (c: c + c) (stringToCharacters cleanHex))
        else if stringLength cleanHex == 4 then
          concatStrings (map (c: c + c) (stringToCharacters cleanHex))
        else
          cleanHex # Already 6 or 8
      );
      r = substring 0 2 normalizedHex;
      g = substring 2 2 normalizedHex;
      b = substring 4 2 normalizedHex;
    in if stringLength normalizedHex == 8 then
      { inherit r g b; alpha = substring 6 2 normalizedHex; }
    else
      { inherit r g b; alpha = "FF"; };

  combineHex = { r, g, b, alpha ? "FF" }:
    let
      padHex = hex: if stringLength hex == 1 then "0${hex}" else hex;
      result = toUpper "#${padHex r}${padHex g}${padHex b}${if (toUpper alpha) != "FF" then (padHex alpha) else ""}";
    in if isValidHex result then result else throw "Invalid combined hex: ${result}";

  # --- Hex <-> RGB Conversion (using new helpers) ---

  # Converts a hex color string (e.g., "#RRGGBB", "RGB", "#RGBA", etc.) to an RGB attribute set { r, g, b } with values 0.0-1.0, plus the original alpha hex string.
  hexToRgb = hex:
    let parts = splitHex hex; # parts = { r, g, b, alpha } as hex strings
    in {
      r = (hexToDec parts.r) / 255.0;
      g = (hexToDec parts.g) / 255.0;
      b = (hexToDec parts.b) / 255.0;
      alpha = parts.alpha; # Keep alpha as hex string "FF", "80", etc.
    };

  # Converts an RGB attribute set { r, g, b } (values 0.0-1.0) and an alpha hex string { alpha } to a hex color string "#RRGGBBAA" or "#RRGGBB"
  rgbToHex = rgbWithAlpha: # Expects { r, g, b, alpha } where alpha is hex string
    let
      # Use lib.toHexString for cleaner byte conversion
      toHexByte = val: lib.toHexString (builtins.floor (clamp val 0.0 1.0 * 255.0 + 0.5)); # Add 0.5 for rounding
    in combineHex {
      r = toHexByte rgbWithAlpha.r;
      g = toHexByte rgbWithAlpha.g;
      b = toHexByte rgbWithAlpha.b;
      alpha = rgbWithAlpha.alpha; # Pass the original alpha hex string
    };

  # --- Color Manipulation Functions ---

  # Generic function to modify a component of a color model, preserving alpha
  modifyComponent = modelConversionFunc: inverseModelConversionFunc: componentName: modifierFunc: hexColor:
    let
      # 1. Convert hex to RGB + Alpha (hex string)
      rgbWithAlpha = hexToRgb hexColor;
      rgbOnly = { r = rgbWithAlpha.r; g = rgbWithAlpha.g; b = rgbWithAlpha.b; };
      originalAlpha = rgbWithAlpha.alpha;

      # 2. Convert RGB to target model (e.g., Okhsl)
      modelColor = modelConversionFunc rgbOnly;

      # 3. Modify the component in the target model
      modifiedValue = modifierFunc modelColor.${componentName};
      modifiedModelColor = modelColor // { ${componentName} = modifiedValue; }; # Update the specific component

      # 4. Convert back to RGB
      modifiedRgbOnly = inverseModelConversionFunc modifiedModelColor;

      # 5. Combine modified RGB with original Alpha and convert back to hex
      modifiedRgbWithAlpha = modifiedRgbOnly // { alpha = originalAlpha; };
    in rgbToHex modifiedRgbWithAlpha;

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

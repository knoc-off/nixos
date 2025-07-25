{ lib ? import <nixpkgs/lib>, math ? import ../math.nix { inherit lib; }
, colorMath ? import ./color-math.nix { inherit lib math; } }:

let
  inherit (lib)
    stringToCharacters toUpper removePrefix stringLength elem all concatStrings
    substring map filter;
  inherit (math) clamp; # Removed hexToDec from math
  inherit (colorMath) srgb_to_okhsl okhsl_to_srgb srgb_to_okhsv okhsv_to_srgb;
  epsilon = 1.0e-8;

  # --- Hex Helpers (copied from color-tests.nix) ---

  hexDigitToDec = hexDigit:
    let
      hexChars = {
        "0" = 0;
        "1" = 1;
        "2" = 2;
        "3" = 3;
        "4" = 4;
        "5" = 5;
        "6" = 6;
        "7" = 7;
        "8" = 8;
        "9" = 9;
        "A" = 10;
        "B" = 11;
        "C" = 12;
        "D" = 13;
        "E" = 14;
        "F" = 15;
        "a" = 10;
        "b" = 11;
        "c" = 12;
        "d" = 13;
        "e" = 14;
        "f" = 15;
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
        if digits == [ ] then
          acc
        else
          let
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
      validChars =
        [ "0" "1" "2" "3" "4" "5" "6" "7" "8" "9" "A" "B" "C" "D" "E" "F" ];
      chars = stringToCharacters (toUpper cleanHex);
      validLengths = [ 3 4 6 8 ];
      isValidLength = elem (stringLength cleanHex) validLengths;
    in isValidLength && all (c: elem c validChars) chars;

  splitHex = hex:
    let
      cleanHex = removePrefix "#" hex;
      _ = if !(isValidHex cleanHex) then
        throw "Invalid hex color code: ${hex}"
      else
        true;
      normalizedHex = toUpper (if stringLength cleanHex == 3 then
        concatStrings (map (c: c + c) (stringToCharacters cleanHex))
      else if stringLength cleanHex == 4 then
        concatStrings (map (c: c + c) (stringToCharacters cleanHex))
      else
        cleanHex # Already 6 or 8
      );
      r = substring 0 2 normalizedHex;
      g = substring 2 2 normalizedHex;
      b = substring 4 2 normalizedHex;
    in if stringLength normalizedHex == 8 then {
      inherit r g b;
      alpha = substring 6 2 normalizedHex;
    } else {
      inherit r g b;
      alpha = "FF";
    };

  combineHex = { r, g, b, alpha ? "FF" }:
    let
      padHex = hex: if stringLength hex == 1 then "0${hex}" else hex;
      result = toUpper "${padHex r}${padHex g}${padHex b}${
          if (toUpper alpha) != "FF" then (padHex alpha) else ""
        }";
    in if isValidHex result then
      result
    else
      throw "Invalid combined hex: ${result}";

  # --- Hex <-> RGB Conversion (using new helpers) ---

  # Converts a hex color string (e.g., "#RRGGBB", "RGB", "#RGBA", etc.) to an RGB attribute set { r, g, b, alpha } with values 0.0-1.0.
  hexToRgb = hex:
    let parts = splitHex hex; # parts = { r, g, b, alpha } as hex strings
    in {
      r = (hexToDec parts.r) / 255.0;
      g = (hexToDec parts.g) / 255.0;
      b = (hexToDec parts.b) / 255.0;
      alpha = (hexToDec parts.alpha)
        / 255.0; # Convert alpha hex to float 0.0-1.0
    };

  # Converts an RGB attribute set { r, g, b, alpha } (values 0.0-1.0) to a hex color string "#RRGGBBAA" or "#RRGGBB" (if alpha is 1.0)
  rgbToHex =
    rgbWithFloatAlpha: # Expects { r, g, b, alpha } where alpha is float
    let
      # Use lib.toHexString for cleaner byte conversion
      toHexByte = val:
        lib.toHexString (builtins.floor
          (clamp val 0.0 1.0 * 255.0 + 0.5)); # Add 0.5 for rounding
      alphaFloat = clamp rgbWithFloatAlpha.alpha 0.0 1.0;
      # Only include alpha hex if alpha is noticeably less than 1.0
      alphaHex =
        if alphaFloat >= (1.0 - epsilon) then "FF" else toHexByte alphaFloat;
    in combineHex {
      r = toHexByte rgbWithFloatAlpha.r;
      g = toHexByte rgbWithFloatAlpha.g;
      b = toHexByte rgbWithFloatAlpha.b;
      alpha = alphaHex; # Pass hex alpha, combineHex handles omitting "FF"
    };

  # --- Color Manipulation Functions ---

  # Generic function to modify a component of a color model, preserving alpha
  modifyComponent =
    modelConversionFunc: inverseModelConversionFunc: componentName: modifierFunc: hexColor:
    let
      # 1. Convert hex to RGB + Alpha (float)
      rgbWithFloatAlpha = hexToRgb hexColor;
      rgbOnly = {
        r = rgbWithFloatAlpha.r;
        g = rgbWithFloatAlpha.g;
        b = rgbWithFloatAlpha.b;
      };
      originalFloatAlpha = rgbWithFloatAlpha.alpha; # Alpha is now a float

      # 2. Convert RGB to target model (e.g., Okhsl)
      modelColor = modelConversionFunc rgbOnly;

      # 3. Modify the component in the target model
      modifiedValue = modifierFunc modelColor.${componentName};
      modifiedModelColor = modelColor // {
        ${componentName} = modifiedValue;
      }; # Update the specific component

      # 4. Convert back to RGB
      modifiedRgbOnly = inverseModelConversionFunc modifiedModelColor;

      # 5. Combine modified RGB with original float Alpha and convert back to hex
      modifiedRgbWithFloatAlpha = modifiedRgbOnly // {
        alpha = originalFloatAlpha;
      };
    in rgbToHex modifiedRgbWithFloatAlpha;

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
      wrappedModifier = currentHue:
        math.fmod (modifierFunc currentHue) 1.0; # Ensure hue wraps
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
      wrappedModifier = currentHue:
        math.fmod (modifierFunc currentHue) 1.0; # Ensure hue wraps
    in modifyComponent srgb_to_okhsv okhsv_to_srgb "h" wrappedModifier hexColor;

  # --- Convenience Functions ---

  # Set Okhsl Lightness to a specific value
  setOkhslLightness = newL: hexColor: modifyOkhslLightness (_: newL) hexColor;

  # Adjust Okhsl Lightness by an amount (e.g., adjustOkhslLightness 0.1 increases lightness by 0.1)
  adjustOkhslLightness = deltaL: hexColor:
    modifyOkhslLightness (currentL: clamp (currentL + deltaL) 0.0 1.0) hexColor;

  # Scale Okhsl Lightness by a factor (e.g., scaleOkhslLightness 1.1 increases lightness by 10%)
  scaleOkhslLightness = factorL: hexColor:
    modifyOkhslLightness (currentL: clamp (currentL * factorL) 0.0 1.0)
    hexColor;

  # Set Okhsl Saturation
  setOkhslSaturation = newS: hexColor: modifyOkhslSaturation (_: newS) hexColor;

  # Adjust Okhsl Saturation
  adjustOkhslSaturation = deltaS: hexColor:
    modifyOkhslSaturation (currentS: clamp (currentS + deltaS) 0.0 1.0)
    hexColor;

  # Scale Okhsl Saturation
  scaleOkhslSaturation = factorS: hexColor:
    modifyOkhslSaturation (currentS: clamp (currentS * factorS) 0.0 1.0)
    hexColor;

  # Set Okhsl Hue
  setOkhslHue = newH: hexColor: modifyOkhslHue (_: newH) hexColor;

  # Adjust Okhsl Hue (rotate hue)
  adjustOkhslHue = deltaH: hexColor:
    modifyOkhslHue (currentH: currentH + deltaH)
    hexColor; # Wrapping handled by modifyOkhslHue

  # Set Okhsv Value
  setOkhsvValue = newV: hexColor: modifyOkhsvValue (_: newV) hexColor;

  # Adjust Okhsv Value
  adjustOkhsvValue = deltaV: hexColor:
    modifyOkhsvValue (currentV: clamp (currentV + deltaV) 0.0 1.0) hexColor;

  # Scale Okhsv Value
  scaleOkhsvValue = factorV: hexColor:
    modifyOkhsvValue (currentV: clamp (currentV * factorV) 0.0 1.0) hexColor;

  # Set Okhsv Saturation
  setOkhsvSaturation = newS: hexColor: modifyOkhsvSaturation (_: newS) hexColor;

  # Adjust Okhsv Saturation
  adjustOkhsvSaturation = deltaS: hexColor:
    modifyOkhsvSaturation (currentS: clamp (currentS + deltaS) 0.0 1.0)
    hexColor;

  # Scale Okhsv Saturation
  scaleOkhsvSaturation = factorS: hexColor:
    modifyOkhsvSaturation (currentS: clamp (currentS * factorS) 0.0 1.0)
    hexColor;

  # Set Okhsv Hue
  setOkhsvHue = newH: hexColor: modifyOkhsvHue (_: newH) hexColor;

  # Adjust Okhsv Hue (rotate hue)
  adjustOkhsvHue = deltaH: hexColor:
    modifyOkhsvHue (currentH: currentH + deltaH)
    hexColor; # Wrapping handled by modifyOkhsvHue

  # --- Component Getter Functions ---

  # Generic function to get a component from a specific color model
  getComponent = modelConversionFunc: componentName: hexColor:
    let
      # 1. Convert hex to RGB + Alpha (float)
      rgbWithFloatAlpha = hexToRgb hexColor;
      rgbOnly = {
        r = rgbWithFloatAlpha.r;
        g = rgbWithFloatAlpha.g;
        b = rgbWithFloatAlpha.b;
      };

      # 2. Convert RGB to target model (e.g., Okhsl)
      modelColor = modelConversionFunc rgbOnly;

      # 3. Return the requested component
    in modelColor.${componentName};

  # --- Okhsl Getters ---
  getOkhslLightness = hexColor: getComponent srgb_to_okhsl "l" hexColor;
  getOkhslSaturation = hexColor: getComponent srgb_to_okhsl "s" hexColor;
  getOkhslHue = hexColor: getComponent srgb_to_okhsl "h" hexColor;

  # --- Okhsv Getters ---
  getOkhsvValue = hexColor: getComponent srgb_to_okhsv "v" hexColor;
  getOkhsvSaturation = hexColor: getComponent srgb_to_okhsv "s" hexColor;
  getOkhsvHue = hexColor: getComponent srgb_to_okhsv "h" hexColor;

  # Color Mixing function using Okhsl
  mixColors = color1: color2: ratio:
    let
      rgb1 = hexToRgb color1;
      rgb2 = hexToRgb color2;

      okhsl1 = srgb_to_okhsl {
        r = rgb1.r;
        g = rgb1.g;
        b = rgb1.b;
      };
      okhsl2 = srgb_to_okhsl {
        r = rgb2.r;
        g = rgb2.g;
        b = rgb2.b;
      };

      # Interpolate Alpha
      alpha = rgb1.alpha * (1.0 - ratio) + rgb2.alpha * ratio;

      # Interpolate Lightness and Saturation
      l = okhsl1.l * (1.0 - ratio) + okhsl2.l * ratio;
      s = okhsl1.s * (1.0 - ratio) + okhsl2.s * ratio;

      # Interpolate Hue (handle wrap-around)
      h1 = okhsl1.h;
      h2 = okhsl2.h;
      diff = h2 - h1;
      dist = math.abs diff;

      # Adjust hues for shortest path interpolation if distance > 0.5
      h1_adj = if dist > 0.5 && diff > 0.0 then h1 + 1.0 else h1;
      h2_adj = if dist > 0.5 && diff < 0.0 then h2 + 1.0 else h2;

      # Interpolate adjusted hues and wrap result
      h_interpolated = h1_adj * (1.0 - ratio) + h2_adj * ratio;
      h = math.fmod h_interpolated 1.0;

      # Convert back
      mixed_okhsl = { inherit h s l; };
      mixed_rgb_only = okhsl_to_srgb mixed_okhsl;
      mixed_rgb_alpha = mixed_rgb_only // { inherit alpha; };
    in rgbToHex mixed_rgb_alpha;

  # Match Lightness and Saturation
  # Takes two hex colors: colorToModify and referenceColor.
  # Returns colorToModify with its Okhsl lightness and saturation set to match referenceColor.
  matchLightnessSaturation = colorToModify: referenceColor:
    let
      targetL = getOkhslLightness referenceColor;
      targetS = getOkhslSaturation referenceColor;
      # Apply the target lightness first
      modifiedLightness = setOkhslLightness targetL colorToModify;
      # Then apply the target saturation to the result
      finalColor = setOkhslSaturation targetS modifiedLightness;
    in finalColor;

  invertColorOkhsv = hexColor:
    let
      # Flip hue by 180 degrees (0.5 in 0-1 range)
      hueFlipped = adjustOkhsvHue 0.5 hexColor;
      # Invert value (1 - v) for maximum contrast
      currentValue = getOkhsvValue hexColor;
    in setOkhsvValue (1.0 - currentValue) hueFlipped;

  contrastRatio = colorA: colorB:
    let
      rgbA = hexToRgb colorA;
      rgbB = hexToRgb colorB;
      luminance = { r, g, b, ... }: 0.2126 * r + 0.7152 * g + 7.22e-2 * b;
      l1 = (luminance rgbA) + 5.0e-2;
      l2 = (luminance rgbB) + 5.0e-2;
    in (if l1 > l2 then l1 / l2 else l2 / l1);

  # Adjust one color to contrast with a fixed reference color using Okhsv
  adjustContrastAgainstFixed = fixedColor: colorToAdjust: factor:
    let
      # Get Okhsv components
      fixedValue = getOkhsvValue fixedColor;
      fixedHue = getOkhsvHue fixedColor;
      currentValue = getOkhsvValue colorToAdjust;
      currentHue = getOkhsvHue colorToAdjust;

      # Value adjustment: push away from fixed color's value
      valueDelta = if fixedValue > 0.5 then
        (0.0 - currentValue) # Fixed is light, push to dark
      else
        (1.0 - currentValue); # Fixed is dark, push to light
      newValue = clamp (currentValue + valueDelta * factor) 0.0 1.0;

      # Hue adjustment: move to opposite side of hue circle
      targetHue = math.fmod (fixedHue + 0.5) 1.0;
      hueDelta = let raw = targetHue - currentHue;
      in if raw > 0.5 then raw - 1.0 else if raw < -0.5 then raw + 1.0 else raw;
      newHue = math.fmod (currentHue + hueDelta * factor) 1.0;

      modified = setOkhsvHue newHue (setOkhsvValue newValue colorToAdjust);
    in modified;

  ensureTextContrast = textColor: backgroundColor: minRatio:
    let
      currentRatio = contrastRatio textColor backgroundColor;
      neededBoost = (minRatio - currentRatio) / 3.0;
      factor = clamp neededBoost 0.0 1.0;
    in adjustContrastAgainstFixed backgroundColor textColor factor;

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

  # Export component getter functions
  inherit getOkhslLightness getOkhslSaturation getOkhslHue;
  inherit getOkhsvValue getOkhsvSaturation getOkhsvHue;

  # Export the color mixing function
  inherit mixColors;

  # export the color invert function
  inherit invertColorOkhsv ensureTextContrast contrastRatio
    adjustContrastAgainstFixed;

  # Export the matching function
  inherit matchLightnessSaturation;
}

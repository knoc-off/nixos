{ lib ? import <nixpkgs/lib>, }:

let
  abs = x: if x < 0 then (-1) * x else x;

  functions = rec {
    # Function to check if a string contains only valid hex characters
    isValidHex = str:
      let
        validChars = [
          "0" "1" "2" "3" "4" "5" "6" "7" "8" "9"
          "A" "B" "C" "D" "E" "F"
          "a" "b" "c" "d" "e" "f" # could remove this row, by converting to upper
        ];
        chars = lib.stringToCharacters str;
        validLengths = [3 4 6 8];
        isValidLength = builtins.elem (builtins.stringLength str) validLengths;
      in
        isValidLength && builtins.all (c: builtins.elem c validChars) chars;

    # put these into the Math Lib
    clampF = x: min: max: lib.min max (lib.max min x);
    clamp = x: min: max: builtins.floor (lib.min max (lib.max min x) + 0.5);
    fmod = x: y: x - y * builtins.floor (x / y);


    normHex = hex: convert.combineHex (convert.splitHex hex);
    removeAlpha = hex: builtins.substring 0 6 (normHex hex);

    convert = rec {
      decToHex = dec: lib.toHexString dec;

      hexToDec = hexStr:
        let
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
              };
              upperHexDigit = lib.toUpper hexDigit;
            in if builtins.hasAttr upperHexDigit hexChars then
              hexChars.${upperHexDigit}
            else
              throw "Invalid hex digit: ${hexDigit}";

          upperHex = lib.toUpper hexStr;
          hexDigits = lib.stringToCharacters upperHex;

          # Helper function to recursively calculate the decimal value
          hexToDecHelper = digits: acc:
            if digits == [ ] then
              acc
            else
              let
                digit = builtins.head digits;
                remainingDigits = builtins.tail digits;
                digitValue = hexDigitToDec digit;
              in hexToDecHelper remainingDigits (acc * 16 + digitValue);
        in hexToDecHelper hexDigits 0;

      splitHex = hex:
        let
          # Remove the "#" if present
          cleanHex = builtins.replaceStrings [ "#" ] [ "" ] hex;

          validationResult = isValidHex cleanHex;

          # Normalize the hex code
          normalizedHex = if builtins.stringLength cleanHex == 3 then
          # Expand 3-digit hex to 6-digit
            lib.concatStrings (map (c: c + c) (lib.stringToCharacters cleanHex))
          else if builtins.stringLength cleanHex == 4 then
          # Expand 4-digit hex (with alpha) to 8-digit
            lib.concatStrings (map (c: c + c) (lib.stringToCharacters cleanHex))
          else if builtins.stringLength cleanHex == 6
          || builtins.stringLength cleanHex == 8 then
            cleanHex
          else
            throw "Invalid hex color code (wrong length): ${hex}";

          # Split the normalized hex code into components
          r = builtins.substring 0 2 normalizedHex;
          g = builtins.substring 2 2 normalizedHex;
          b = builtins.substring 4 2 normalizedHex;
          a = if builtins.stringLength normalizedHex == 8 then
            builtins.substring 6 2 normalizedHex
          else
            "FF";

        in if validationResult then {
          inherit r g b a;
        } else
          throw "Invalid hex color code: ${hex}";

      combineHex = {r, g, b, a }:
        let
          padHex = hex:
            if builtins.stringLength hex == 1 then "0${hex}" else hex;
          result = lib.toUpper "${padHex r}${padHex g}${padHex b}${padHex a}";
        in if isValidHex result then result else throw "Invalid hex color code: ${result}";

      hexToRgb = hex:
        let
          c = splitHex hex;
          r = (hexToDec c.r) / 255.0;
          g = (hexToDec c.g) / 255.0;
          b = (hexToDec c.b) / 255.0;
          a = (hexToDec c.a) / 255.0;
        in { inherit r g b a; };

      hexToHsl = hex: rgbToHsl (hexToRgb hex);

      rgbToHex = rgb:
        let
          inherit (rgb) r g b a;
          mut = x: builtins.floor (x * 255.0 + 0.5);
        in combineHex { r = decToHex (mut r); g = decToHex (mut g); b = decToHex (mut b); a = decToHex (mut a); };

      # Convert normalized RGB to HSL
      rgbToHsl = rgb:
        let
          inherit (rgb) r g b a;
          cmax = lib.max r (lib.max g b);
          cmin = lib.min r (lib.min g b);
          delta = cmax - cmin;

          # Compute Hue
          h_unscaled = if delta == 0.0 then
            0.0
          else
            (if cmax == r then
              fmod ((g - b) / delta) 6.0
            else if cmax == g then
              ((b - r) / delta) + 2.0
            else
              ((r - g) / delta) + 4.0);
          h' = h_unscaled * 60.0;
          h = if h' < 0.0 then h' + 360.0 else h';

          # Compute Lightness
          l = (cmax + cmin) / 2.0;

          # Compute Saturation
          s = if delta == 0.0 then 0.0 else delta / (1.0 - abs (2.0 * l - 1.0));
        in { inherit h s l a; };

      # Convert HSL back to RGB
      hslToRgb = hsl:
        let
          inherit (hsl) h s l a;

          c = (1.0 - abs (2.0 * l - 1.0)) * s;
          h_prime = h / 60.0;
          x = c * (1.0 - abs (fmod h_prime 2.0 - 1.0));
          m = l - c / 2.0;

          rgb' = if h_prime >= 0.0 && h_prime < 1.0 then {
            r = c;
            g = x;
            b = 0.0;
          } else if h_prime >= 1.0 && h_prime < 2.0 then {
            r = x;
            g = c;
            b = 0.0;
          } else if h_prime >= 2.0 && h_prime < 3.0 then {
            r = 0.0;
            g = c;
            b = x;
          } else if h_prime >= 3.0 && h_prime < 4.0 then {
            r = 0.0;
            g = x;
            b = c;
          } else if h_prime >= 4.0 && h_prime < 5.0 then {
            r = x;
            g = 0.0;
            b = c;
          } else if h_prime >= 5.0 && h_prime < 6.0 then {
            r = c;
            g = 0.0;
            b = x;
          } else {
            r = 0.0;
            g = 0.0;
            b = 0.0;
          };
        in {
          r = rgb'.r + m;
          g = rgb'.g + m;
          b = rgb'.b + m;
          inherit a;
        };

      hslToHex = hsl: rgbToHex (hslToRgb hsl);

    };

  universal = rec { # i dont know if i should keep this. enforces bad practice?
    toHex = value:
      let
        format = helper.determineColorFormat value;
      in
        if format == "hex" then normHex value
        else if format == "rgb" then convert.rgbToHex value
        else if format == "hsl" then convert.hslToHex value
        else throw "Invalid color format for conversion to hex";

    toRgb = value:
      let
        format = helper.determineColorFormat value;
      in
        if format == "hex" then convert.hexToRgb value
        else if format == "rgb" then value
        else if format == "hsl" then convert.hslToRgb value
        else throw "Invalid color format for conversion to RGB";

    toHsl = value:
      let
        format = helper.determineColorFormat value;
      in
        if format == "hex" then convert.hexToHsl value
        else if format == "rgb" then convert.rgbToHsl value
        else if format == "hsl" then value
        else throw "Invalid color format for conversion to HSL";

  };

  helper = rec {
    isHex = value:
      if builtins.isString value then
        let
          cleanStr = builtins.replaceStrings ["#"] [""] value;
        in
          isValidHex cleanStr
      else
        false;

    isRgb = value:
      builtins.isAttrs value &&
      builtins.all (k: builtins.hasAttr k value) ["r" "g" "b"] &&
      builtins.all (k: builtins.isFloat value.${k} && value.${k} >= 0 && value.${k} <= 1) ["r" "g" "b"];

    isHsl = value:
      builtins.isAttrs value &&
      builtins.all (k: builtins.hasAttr k value) ["h" "s" "l"] &&
      builtins.isFloat value.h && value.h >= 0 && value.h < 360 &&
      builtins.isFloat value.s && value.s >= 0 && value.s <= 1 &&
      builtins.isFloat value.l && value.l >= 0 && value.l <= 1;

    # Main function to determine color format
    determineColorFormat = value:
      if isHex value then
        "hex"
      else if isRgb value then
        "rgb"
      else if isHsl value then
        "hsl"
      else
        throw "Unknown color format";
    };
  };
in functions

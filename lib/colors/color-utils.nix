{ lib ? import <nixpkgs/lib>, }:
let
  inherit (import ./math.nix { inherit lib; }) tan atan sin cos abs sqrt pow cbrt pi;

  functions = rec {
    # Function to check if a string contains only valid hex characters
    isValidHex = str:
      let
        validChars = [
          "0" "1" "2" "3" "4" "5" "6" "7" "8" "9"
          "A" "B" "C" "D" "E" "F"
        ];
        chars = lib.stringToCharacters (lib.toUpper str);
        validLengths = [3 4 6 8];
        isValidLength = builtins.elem (builtins.stringLength str) validLengths;
      in
        isValidLength && builtins.all (c: builtins.elem c validChars) chars;

    # Custom min and max functions for floats
    fmin = x: y: if x < y then x else y;
    fmax = x: y: if x > y then x else y;

    # Clamp functions using custom fmin and fmax
    clampF = x: min: max: fmin max (fmax min x);
    clamp = x: min: max: builtins.floor (fmin max (fmax min x) + 0.5);

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
            if digits == [] then
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
          else if builtins.elem (builtins.stringLength cleanHex) [6 8] then
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
        }
        else
          throw "Invalid hex color code: ${hex}";

      combineHex = { r, g, b, a }:
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

      rgbToHex = rgb:
        let
          inherit (rgb) r g b a;
          mut = x: builtins.floor (x * 255.0 + 0.5);
        in combineHex {
          r = decToHex (mut r);
          g = decToHex (mut g);
          b = decToHex (mut b);
          a = decToHex (mut a);
        };

      # Convert normalized RGB to HSL
      rgbToHsl = rgb:
        let
          inherit (rgb) r g b a;
          cmax = fmax r (fmax g b);
          cmin = fmin r (fmin g b);
          delta = cmax - cmin;

          # Compute Hue
          h_unscaled = if delta == 0.0 then
                        0.0
                      else if cmax == r then
                        fmod ((g - b) / delta) 6.0
                      else if cmax == g then
                        ((b - r) / delta) + 2.0
                      else
                        ((r - g) / delta) + 4.0;
          h' = h_unscaled * 60.0;
          h = if h' < 0.0 then h' + 360.0 else h';

          # Compute Lightness
          l = (cmax + cmin) / 2.0;

          # Compute Saturation
          s = if delta == 0.0 then
                0.0
              else
                delta / (1.0 - abs (2.0 * l - 1.0));
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
                  }
                 else if h_prime >= 1.0 && h_prime < 2.0 then {
                    r = x;
                    g = c;
                    b = 0.0;
                  }
                 else if h_prime >= 2.0 && h_prime < 3.0 then {
                    r = 0.0;
                    g = c;
                    b = x;
                  }
                 else if h_prime >= 3.0 && h_prime < 4.0 then {
                    r = 0.0;
                    g = x;
                    b = c;
                  }
                 else if h_prime >= 4.0 && h_prime < 5.0 then {
                    r = x;
                    g = 0.0;
                    b = c;
                  }
                 else if h_prime >= 5.0 && h_prime < 6.0 then {
                    r = c;
                    g = 0.0;
                    b = x;
                  }
                 else {
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

      # RGB to Oklab conversion
      rgbToOklab = rgb:
        let
          inherit (rgb) r g b;

          # Convert linear RGB to Oklab
          l = 0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b;
          m = 0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b;
          s = 0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b;

          l_ = cbrt l;
          m_ = cbrt m;
          s_ = cbrt s;

          L = 0.2104542553 * l_ + 0.7936177850 * m_ - 0.0040720468 * s_;
          a = 1.9779984951 * l_ - 2.4285922050 * m_ + 0.4505937099 * s_;
          b' = 0.0259040371 * l_ + 0.7827717662 * m_ - 0.8086757660 * s_;
        in {
          L = L;
          a = a;
          b = b';
          alpha = if builtins.hasAttr "a" rgb then rgb.a else 1.0;
        };

      # Oklab to RGB conversion
      oklabToRgb = oklab:
        let
          inherit (oklab) L a b;

          l_ = L + 0.3963377774 * a + 0.2158037573 * b;
          m_ = L - 0.1055613458 * a - 0.0638541728 * b;
          s_ = L - 0.0894841775 * a - 1.2914855480 * b;

          l = pow l_ 3;
          m = pow m_ 3;
          s = pow s_ 3;

          r =  4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s;
          g = -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s;
          b' = -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s;

        in {
          r = clampF r 0.0 1.0;
          g = clampF g 0.0 1.0;
          b = clampF b' 0.0 1.0;
          a = if builtins.hasAttr "alpha" oklab then oklab.alpha else 1.0;
        };

      # Hex to Oklab conversion
      hexToOklab = hex: rgbToOklab (hexToRgb hex);

      # Oklab to Hex conversion
      oklabToHex = oklab: rgbToHex (oklabToRgb oklab);

      # Oklab to OKHSL conversion
      oklabToOkhsl = oklab:
        let
          inherit (oklab) L a b;

          C = sqrt (a * a + b * b);
          h' = atan (b / a);
          h = if h' < 0 then (h' / (2 * pi)) + 1 else h' / (2 * pi);

          # Replaced pow (x / 32768) 3.0 with (x / 32768) * (x / 32768) * (x / 32768)
          # Replaced pow (...) (1.0 / 3.0) with cbrt (...)
          toe = x:
            if x >= 0 then
              0.5 * (cbrt (1 + (x / 32768) * (x / 32768) * (x / 32768)) - 1)
            else
              -(0.5 * (cbrt (1 + (-x / 32768) * (-x / 32768) * (-x / 32768)) - 1));

          # Replaced pow (...) 3.0 with (...) * (...) * (...)
          toe_inv = x:
            if x >= 0 then
              32768 * (1 + 2 * x) * (1 + 2 * x) * (1 + 2 * x)
            else
              -32768 * (1 - 2 * x) * (1 - 2 * x) * (1 - 2 * x);

          l = toe L;
          s = if l != 0.0 && l != 1.0 then C / (toe_inv l) else 0.0;
        in {
          h = clampF h 0.0 1.0;
          s = clampF s 0.0 1.0;
          l = clampF l 0.0 1.0;
          a = if builtins.hasAttr "alpha" oklab then oklab.alpha else 1.0;
        };

      # OKHSL to Oklab conversion
      okhslToOklab = okhsl:
        let
          inherit (okhsl) h s l;

          # Replaced pow (x / 32768) 3.0 with (x / 32768) * (x / 32768) * (x / 32768)
          # Replaced pow (...) (1.0 / 3.0) with cbrt (...)
          toe = x:
            if x >= 0 then
              0.5 * (cbrt (1 + (x / 32768) * (x / 32768) * (x / 32768)) - 1)
            else
              -(0.5 * (cbrt (1 + (-x / 32768) * (-x / 32768) * (-x / 32768)) - 1));

          # Replaced pow (...) 3.0 with (...) * (...) * (...)
          toe_inv = x:
            if x >= 0 then
              32768 * (1 + 2 * x) * (1 + 2 * x) * (1 + 2 * x)
            else
              -32768 * (1 - 2 * x) * (1 - 2 * x) * (1 - 2 * x);

          C = s * toe_inv l;
          a = C * cos (h * 2 * pi);
          b = C * sin (h * 2 * pi);
          L = toe_inv l;
        in {
          L = L;
          a = a;
          b = b;
          alpha = if builtins.hasAttr "a" okhsl then okhsl.a else 1.0;
        };

      # Hex to OKHSL conversion
      hexToOkhsl = hex:
        let
          rgb = hexToRgb hex;
          oklab = rgbToOklab rgb;
        in oklabToOkhsl oklab;

      # OKHSL to Hex conversion
      okhslToHex = okhsl:
        let
          oklab = okhslToOklab okhsl;
          rgb = oklabToRgb oklab;
        in rgbToHex rgb;

      # RGB to OKHSL conversion
      rgbToOkhsl = rgb:
        let
          oklab = rgbToOklab rgb;
        in oklabToOkhsl oklab;

      # OKHSL to RGB conversion
      okhslToRgb = okhsl:
        let
          oklab = okhslToOklab okhsl;
        in oklabToRgb oklab;

      # HSL to OKHSL conversion
      hslToOkhsl = hsl:
        let
          rgb = hslToRgb hsl;
        in rgbToOkhsl rgb;

      # OKHSL to HSL conversion
      okhslToHsl = okhsl:
        let
          rgb = okhslToRgb okhsl;
        in rgbToHsl rgb;
    };

    universal = rec { # Note: Evaluate if keeping this is appropriate based on your project needs
      toHex = value:
        let
          format = helper.determineColorFormat value;
        in
          if format == "hex" then normHex value
          else if format == "rgb" then convert.rgbToHex value
          else if format == "hsl" then convert.hslToHex value
          else if format == "okhsl" then convert.okhslToHex (if helper.isOklab value then convert.oklabToOkhsl value else value)
          else if format == "oklab" then convert.oklabToHex value
          else throw "Invalid color format for conversion to hex";

      toRgb = value:
        let
          format = helper.determineColorFormat value;
        in
          if format == "hex" then convert.hexToRgb value
          else if format == "rgb" then value
          else if format == "hsl" then convert.hslToRgb value
          else if format == "okhsl" then convert.okhslToRgb value
          else if format == "oklab" then convert.oklabToRgb value
          else throw "Invalid color format for conversion to RGB";

      toHsl = value:
        let
          format = helper.determineColorFormat value;
        in
          if format == "hex" then convert.hexToHsl value
          else if format == "rgb" then convert.rgbToHsl value
          else if format == "hsl" then value
          else if format == "okhsl" then convert.okhslToHsl value
          else if format == "oklab" then convert.oklabToHsl (convert.oklabToRgb value)
          else throw "Invalid color format for conversion to HSL";

      toOklab = value:
        let
          format = helper.determineColorFormat value;
        in
          if format == "hex" then convert.hexToOklab value
          else if format == "rgb" then convert.rgbToOklab value
          else if format == "hsl" then convert.rgbToOklab (convert.hslToRgb value)
          else if format == "okhsl" then convert.okhslToOklab value
          else if format == "oklab" then value
          else throw "Invalid color format for conversion to Oklab";

      toOkhsl = value:
        let
          format = helper.determineColorFormat value;
        in
          if format == "hex" then convert.hexToOkhsl value
          else if format == "rgb" then convert.rgbToOkhsl value
          else if format == "hsl" then convert.hslToOkhsl value
          else if format == "oklab" then convert.oklabToOkhsl value
          else if format == "okhsl" then value
          else throw "Invalid color format for conversion to OKHSL";

      fromOkhsl = value: format:
        let
          okhsl = if helper.isOkhsl value then value else universal.toOkhsl value;
        in
          if format == "hex" then convert.okhslToHex okhsl
          else if format == "rgb" then convert.okhslToRgb okhsl
          else if format == "hsl" then convert.okhslToHsl okhsl
          else if format == "oklab" then convert.okhslToOklab okhsl
          else if format == "okhsl" then okhsl
          else throw "Invalid target format for conversion from OKHSL";
    };

    helper = rec {
      isOklab = value:
        builtins.isAttrs value &&
        builtins.all (k: builtins.hasAttr k value) ["L" "a" "b"] &&
        builtins.isFloat value.L && value.L >= 0 && value.L <= 1 &&
        builtins.isFloat value.a &&
        builtins.isFloat value.b;

      isOkhsl = value:
        builtins.isAttrs value &&
        builtins.all (k: builtins.hasAttr k value) ["h" "s" "l"] &&
        builtins.all (k: builtins.isFloat value.${k}) ["h" "s" "l"] &&
        value.h >= 0 && value.h <= 1 &&
        value.s >= 0 && value.s <= 1 &&
        value.l >= 0 && value.l <= 1;

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

      determineColorFormat = value:
        if isHex value then
          "hex"
        else if isRgb value then
          "rgb"
        else if isHsl value then
          "hsl"
        else if isOklab value then
          "oklab"
        else if isOkhsl value then
          "okhsl"
        else
          throw "Unknown color format";
    };
  };
in
  functions

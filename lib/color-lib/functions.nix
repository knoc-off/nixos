# color-lib/functions.nix
{ lib ? import <nixpkgs/lib>, math ? { } }:
let
  inherit (import ./math.nix { inherit lib; })
    tan atan sin cos abs sqrt pow cbrt pi powFloat;

  functions = rec {
    mapAttrs = f: set:
      builtins.listToAttrs (map (name: {
        inherit name;
        value = f name set.${name};
      }) (builtins.attrNames set));

    # Function to check if a string contains only valid hex characters
    isValidHex = str:
      let
        validChars =
          [ "0" "1" "2" "3" "4" "5" "6" "7" "8" "9" "A" "B" "C" "D" "E" "F" ];
        chars = lib.stringToCharacters (lib.toUpper str);
        validLengths = [ 3 4 6 8 ];
        isValidLength = builtins.elem (builtins.stringLength str) validLengths;
      in isValidLength && builtins.all (c: builtins.elem c validChars) chars;

    clampF = x: min: max: if x < min then min else if x > max then max else x;
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
          normalizedHex = lib.toUpper
            (if builtins.stringLength cleanHex == 3 then
            # Expand 3-digit hex to 6-digit
              lib.concatStrings
              (map (c: c + c) (lib.stringToCharacters cleanHex))
            else if builtins.stringLength cleanHex == 4 then
            # Expand 4-digit hex (with alpha) to 8-digit
              lib.concatStrings
              (map (c: c + c) (lib.stringToCharacters cleanHex))
            else if builtins.elem (builtins.stringLength cleanHex) [ 6 8 ] then
              cleanHex
            else
              throw "Invalid hex color code (wrong length): ${hex}");

          r = builtins.substring 0 2 normalizedHex;
          g = builtins.substring 2 2 normalizedHex;
          b = builtins.substring 4 2 normalizedHex;
          # Split the normalized hex code into components
          rgb = if builtins.stringLength normalizedHex == 8 then {
            inherit r g b;
            a = builtins.substring 6 2 normalizedHex;
          } else {
            inherit r g b;
          };
        in if validationResult then
          rgb
        else
          throw "Invalid hex color code: ${hex}";

      combineHex = { r, g, b, a ? "FF", ... }@hexa:
        let
          padHex = hex:
            if builtins.stringLength hex == 1 then "0${hex}" else hex;
          result = lib.toUpper "${padHex r}${padHex g}${padHex b}${
              if (lib.toUpper a) != "FF" then (padHex a) else ""
            }";
        in if isValidHex result then
          result
        else
          throw ''
            Invalid hex color code: ${result}
             input: ${builtins.toJSON hexa}'';

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
    };
  };
in functions

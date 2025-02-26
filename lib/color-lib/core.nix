# color-lib/core.nix
{ lib, math }:

let
  inherit (math) pow powFloat hexToDec;
  inherit (builtins) floor stringLength foldl';
  inherit (lib) hasAttr elem all filter head tail isString substring stringToCharacters
    toUpper removePrefix concatStrings concatMap toHexString optional;

  # Hex validation and normalization
  isValidHex = str:
    let
      validChars = ["0" "1" "2" "3" "4" "5" "6" "7" "8" "9" "A" "B" "C" "D" "E" "F"];
      chars = stringToCharacters (toUpper (removePrefix "#" str));
      validLengths = [ 3 4 6 8 ];
      isValidLength = elem (stringLength str) validLengths;
    in isValidLength && all (c: elem c validChars) chars;

  # Hex normalization and splitting
  splitHex = hex:
    let
      # Remove the "#" if present
      cleanHex = removePrefix "#" hex;

      validationResult = isValidHex cleanHex;

      # Normalize the hex code
      normalizedHex = toUpper (
        if stringLength cleanHex == 3 then
          # Expand 3-digit hex to 6-digit
          concatStrings (map (c: c + c) (stringToCharacters cleanHex))
        else if stringLength cleanHex == 4 then
          # Expand 4-digit hex (with alpha) to 8-digit
          concatStrings (map (c: c + c) (stringToCharacters cleanHex))
        else if elem (stringLength cleanHex) [ 6 8 ] then
          cleanHex
        else
          throw "Invalid hex color code (wrong length): ${hex}"
      );

      r = substring 0 2 normalizedHex;
      g = substring 2 2 normalizedHex;
      b = substring 4 2 normalizedHex;
      # Split the normalized hex code into components
      rgb = if stringLength normalizedHex == 8 then {
        inherit r g b;
        alpha = substring 6 2 normalizedHex;
      } else {
        inherit r g b;
        alpha = "FF";
      };
    in if validationResult then
      rgb
    else
      throw "Invalid hex color code: ${hex}";

  combineHex = { r, g, b, alpha ? "FF" }:
    let
      padHex = hex:
        if stringLength hex == 1 then "0${hex}" else hex;
      result = toUpper "${padHex r}${padHex g}${padHex b}${
          if (toUpper alpha) != "FF" then (padHex alpha) else ""
        }";
    in if isValidHex result then
      result
    else
      throw ''
        Invalid hex color code: ${result}
         input: ${builtins.toJSON { inherit r g b alpha; }}'';

in rec {
  # Core color operations
  hex = {
    normalize = hexStr:
      let clean = toUpper (removePrefix "#" hexStr);
      in if stringLength clean == 3 || stringLength clean == 4
         then concatStrings (concatMap (c: [c c]) (stringToCharacters clean))
         else if stringLength clean == 6 || stringLength clean == 8
         then clean
         else throw "Invalid hex format: ${hexStr}";

    toRGB = hexStr:
      let
        c = splitHex hexStr;
        r = (hexToDec c.r) / 255.0;
        g = (hexToDec c.g) / 255.0;
        b = (hexToDec c.b) / 255.0;
        alpha = (hexToDec c.alpha) / 255.0;
      in { inherit r g b alpha; };

    fromRGB = { r, g, b, alpha ? 1.0 }:
      let
        mut = x: floor (x * 255.0 + 0.5);
      in combineHex {
        r = toHexString (mut r);
        g = toHexString (mut g);
        b = toHexString (mut b);
        alpha = toHexString (mut alpha);
      };
  };

  # Color space conversion core
  srgbTransfer = a:
    if a <= 3.1308e-3 then 12.92 * a else 1.055 * powFloat a (1/2.4) - 5.5e-2;

  srgbTransferInv = a:
    if a <= 4.045e-2 then a / 12.92 else powFloat ((a + 5.5e-2) / 1.055) 2.4;

  # Validation and normalization
  normHex = hex: combineHex (splitHex hex);
  removeAlpha = hex: builtins.substring 0 6 (normHex hex);
}


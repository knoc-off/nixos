# color-lib.nix
{ lib ? import <nixpkgs/lib> }:
let

  types = import ./types.nix { };
  math = import ./math.nix {inherit lib;};
  utils = import ./color-utils.nix {inherit lib;};
  hex = import ./formats/hex.nix { inherit utils types; };
  srgb = import ./formats/srgb.nix { inherit math utils types; };
  hsl = import ./formats/hsl.nix { inherit math lib types; };
  oklab = import ./formats/oklab.nix { inherit math lib utils types srgb; };
  okhsl = import ./formats/okhsl.nix { inherit math utils lib types; };
  oklch = import ./formats/oklch.nix {inherit math utils types; };


  hexStrToOklab = hex:
    let
      rg = hexStrToRgb hex;
      rgl = srgb.gammaRgbToLinear rg;
      ok = oklab.xyzToOklab (oklab.linearRgbToXyz rgl);
    in
      ok;

  hexStrToRgb = hex: hex.hexToRgb (hex.splitHex hex);
  rgbToHexStr = rgb: hex.combineHex (hex.rgbToHex rgb);

  # Color manipulation functions
  adjustOkhsl = { color, hueShift ? 0, saturationScale ? 1, lightnessScale ? 1 }:
    let
      newHue = math.mod (color.h + hueShift) 1;
      newSaturation = math.clamp { value = color.s * saturationScale; min = 0; max = 1; };
      newLightness = math.clamp { value = color.l * lightnessScale; min = 0; max = 1; };
    in
    types.Okhsl.check {
      h = newHue;
      s = newSaturation;
      l = newLightness;
    };

  # Wrapper functions
  hexToOkhsl = hex:
    let
      oklab = hexStrToOklab hex;
      oklch = oklch.oklabToOklch oklab;
    in
    oklchToOkhsl oklch;

  okhslToHex = okhsl:
    let
      oklch = okhslToOklch okhsl;
      oklab = oklchToOklab oklch;
      rgb = oklabToRgb oklab;
    in
    rgbToHexStr rgb;

  manipulateHexColor = { hex, hueShift ? 0, saturationScale ? 1, lightnessScale ? 1 }:
    let
      okhsl = hexToOkhsl hex;
      adjustedOkhsl = adjustOkhsl {
        color = okhsl;
        inherit hueShift saturationScale lightnessScale;
      };
    in
    okhslToHex adjustedOkhsl;

in rec {

  inherit (utils.convert) combineHex;

  splitHex = hex: types.Hex.check ( utils.convert.splitHex hex);

  inherit (hex) hexToRgb rgbToHex;
  inherit (hsl) hslToRgb rgbToHsl;

  inherit (oklab) oklabToRgb oklabToLinearRgb linearRgbToXyz xyzToOklab oklabToXyz xyzToLinearRgb;

  inherit types;


  inherit (srgb ) linearToGammaRgb gammaRgbToLinear;

  inherit (okhsl) oklchToOkhsl okhslToOklch;
  inherit (oklch) oklabToOklch oklchToOklab;


  # New color manipulation functions
  inherit adjustOkhsl hexToOkhsl okhslToHex manipulateHexColor;
}

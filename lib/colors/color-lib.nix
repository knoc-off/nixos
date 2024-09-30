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
  #okhsl = import ./formats/okhsl.nix { inherit math utils lib types; };
  #oklch = import ./formats/oklch.nix {inherit math utils types; };
in rec {

  inherit (utils.convert) splitHex combineHex;

  inherit (hex) hexToRgb rgbToHex;
  inherit (hsl) hslToRgb rgbToHsl;
  inherit (srgb) srgbToLinearRgb linearRgbToSrgb;

  inherit (oklab) oklabToRgb oklabToLinearRgb linearRgbToXyz xyzToOklab oklabToXyz xyzToLinearRgb;
}

# color-lib/default.nix
{ lib ? import <nixpkgs/lib>, math ? import ../math.nix { inherit lib; } }:

let
  # Import core functionality
  core = import ./core.nix { inherit lib math; };

  # Import OKLab color space
  oklab = import ./oklab.nix { inherit core math; };

  # Import OKHSL color space
  okhsl = import ./okhsl.nix { inherit core math oklab; };

  # Import OKHSV color space
  okhsv = import ./okhsv.nix { inherit core math oklab; };

  # Import conversion utilities
  conversions = import ./conversions.nix { inherit core oklab okhsl okhsv; };

  # inherit (import ./functions.nix { inherit lib math; })
  #   mapAttrs
  #   isValidHex
  #   clampF
  #   clamp
  #   fmod
  #   normHex
  #   removeAlpha
  #   convert;

in rec {
  # Export all modules
  inherit core oklab okhsl okhsv conversions math;

  # Export version information
  version = "1.0.0";

  # Export combined API
  hex = core.hex;
  srgbTransfer = core.srgbTransfer;
  srgbTransferInv = core.srgbTransferInv;

  # Re-export all conversion functions at top level for convenience
  inherit (conversions)
    hexToRGB rgbToHex rgbToOKLab oklabToRGB rgbToOKHSL okhslToRGB rgbToOKHSV
    okhsvToRGB hexToOKHSL okhslToHex hexToOKHSV okhsvToHex;

  # Utility functions for color manipulation
  mix = color1: color2: ratio:
    let
      lab1 = rgbToOKLab (hexToRGB color1);
      lab2 = rgbToOKLab (hexToRGB color2);
      mixed = {
        L = lab1.L * (1 - ratio) + lab2.L * ratio;
        a = lab1.a * (1 - ratio) + lab2.a * ratio;
        b = lab1.b * (1 - ratio) + lab2.b * ratio;
        alpha = lab1.alpha * (1 - ratio) + lab2.alpha * ratio;
      };
    in rgbToHex (oklabToRGB mixed);

  # Color adjustment functions
  adjustLightness = color: amount:
    let
      hsl = rgbToOKHSL (hexToRGB color);
      newHsl = hsl // { l = core.clamp (hsl.l + amount) 0 1; };
    in okhslToHex newHsl;

  adjustSaturation = color: amount:
    let
      hsl = rgbToOKHSL (hexToRGB color);
      newHsl = hsl // { s = core.clamp (hsl.s + amount) 0 1; };
    in okhslToHex newHsl;

  adjustHue = color: amount:
    let
      hsl = rgbToOKHSL (hexToRGB color);
      newHsl = hsl // { h = math.mod (hsl.h + amount) 1; };
    in okhslToHex newHsl;

  # Color palette generation
  generatePalette = baseColor:
    { lighter ? 0.2, darker ? 0.2, steps ? 5 }:
    let
      hsl = rgbToOKHSL (hexToRGB baseColor);
      stepSize = (darker + lighter) / (steps - 1);
      makeStep = i:
        let
          adjustment = lighter - (stepSize * i);
          newL = core.clamp (hsl.l + adjustment) 0 1;
        in okhslToHex (hsl // { l = newL; });
    in map makeStep (lib.range 0 (steps - 1));
}

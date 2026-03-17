# Color manipulation library backed by builtins.wasm (Determinate Nix).
# Uses the palette crate (Rust) for Oklab/Okhsl/Okhsv math.
#
# All public functions accept hex strings (with or without '#') and return
# hex strings WITHOUT '#', matching the old API contract.
{ lib }:
let
  wasmFile = ./color-lib.wasm;
  w = fn: builtins.wasm { path = wasmFile; function = fn; };

  # -- Internal helpers -----------------------------------------------------

  # Strip '#' so wasm always sees bare hex
  norm = hex: lib.removePrefix "#" hex;

  # hex -> color string (high-precision internal format)
  hexToColorStr = hex: w "hex_to_color" (norm hex);

  # color string -> bare hex
  colorToHex = w "color_to_hex";

  # color string -> okhsl color string
  toOkhsl = cs: w "to_okhsl" cs;

  # color string -> okhsv color string
  toOkhsv = cs: w "to_okhsv" cs;

  # Shorthand: hex -> okhsl color string
  hToOkhsl = hex: toOkhsl (hexToColorStr hex);

  # Shorthand: hex -> okhsv color string
  hToOkhsv = hex: toOkhsv (hexToColorStr hex);

  # color string -> hex (no '#')
  csToHex = cs: colorToHex cs;

in rec {
  # =========================================================================
  # Core conversions
  # =========================================================================

  # hex -> { r, g, b, alpha } (floats 0-1)
  hexToRgb = hex: w "hex_to_rgb_attr" (norm hex);

  # { r, g, b, alpha? } -> hex (no '#')
  rgbToHex = { r, g, b, alpha ? 1.0 }:
    csToHex "srgb:${toString r}:${toString g}:${toString b}:${toString alpha}";

  # =========================================================================
  # Okhsl setters  (value -> hex -> hex)
  # =========================================================================

  setOkhslLightness = val: hex:
    csToHex (w "set_channel" { color = hToOkhsl hex; channel = "l"; value = val; });

  setOkhslSaturation = val: hex:
    csToHex (w "set_channel" { color = hToOkhsl hex; channel = "s"; value = val; });

  setOkhslHue = val: hex:
    csToHex (w "set_channel" { color = hToOkhsl hex; channel = "h"; value = val; });

  # =========================================================================
  # Okhsl adjusters  (delta -> hex -> hex)
  # =========================================================================

  adjustOkhslLightness = delta: hex:
    csToHex (w "adjust_channel" { color = hToOkhsl hex; channel = "l"; amount = delta; });

  adjustOkhslSaturation = delta: hex:
    csToHex (w "adjust_channel" { color = hToOkhsl hex; channel = "s"; amount = delta; });

  adjustOkhslHue = delta: hex:
    csToHex (w "adjust_channel" { color = hToOkhsl hex; channel = "h"; amount = delta; });

  # =========================================================================
  # Okhsl scalers  (factor -> hex -> hex)
  # =========================================================================

  scaleOkhslLightness = factor: hex:
    csToHex (w "scale_channel" { color = hToOkhsl hex; channel = "l"; inherit factor; });

  scaleOkhslSaturation = factor: hex:
    csToHex (w "scale_channel" { color = hToOkhsl hex; channel = "s"; inherit factor; });

  # =========================================================================
  # Okhsv setters / adjusters / scalers
  # =========================================================================

  setOkhsvValue = val: hex:
    csToHex (w "set_channel" { color = hToOkhsv hex; channel = "v"; value = val; });

  setOkhsvSaturation = val: hex:
    csToHex (w "set_channel" { color = hToOkhsv hex; channel = "s"; value = val; });

  setOkhsvHue = val: hex:
    csToHex (w "set_channel" { color = hToOkhsv hex; channel = "h"; value = val; });

  adjustOkhsvValue = delta: hex:
    csToHex (w "adjust_channel" { color = hToOkhsv hex; channel = "v"; amount = delta; });

  adjustOkhsvSaturation = delta: hex:
    csToHex (w "adjust_channel" { color = hToOkhsv hex; channel = "s"; amount = delta; });

  adjustOkhsvHue = delta: hex:
    csToHex (w "adjust_channel" { color = hToOkhsv hex; channel = "h"; amount = delta; });

  scaleOkhsvValue = factor: hex:
    csToHex (w "scale_channel" { color = hToOkhsv hex; channel = "v"; inherit factor; });

  scaleOkhsvSaturation = factor: hex:
    csToHex (w "scale_channel" { color = hToOkhsv hex; channel = "s"; inherit factor; });

  # =========================================================================
  # Getters  (hex -> float)
  # =========================================================================

  getOkhslLightness = hex: w "get_channel" { color = hToOkhsl hex; channel = "l"; };
  getOkhslSaturation = hex: w "get_channel" { color = hToOkhsl hex; channel = "s"; };
  getOkhslHue = hex: w "get_channel" { color = hToOkhsl hex; channel = "h"; };

  getOkhsvValue = hex: w "get_channel" { color = hToOkhsv hex; channel = "v"; };
  getOkhsvSaturation = hex: w "get_channel" { color = hToOkhsv hex; channel = "s"; };
  getOkhsvHue = hex: w "get_channel" { color = hToOkhsv hex; channel = "h"; };

  # =========================================================================
  # Mixing  (hex -> hex -> ratio -> hex)
  # =========================================================================

  mixColors = color1: color2: ratio:
    csToHex (w "mix" {
      a = hexToColorStr color1;
      b = hexToColorStr color2;
      factor = ratio;
    });

  # =========================================================================
  # Contrast
  # =========================================================================

  contrastRatio = colorA: colorB:
    w "contrast_ratio" {
      a = hexToColorStr colorA;
      b = hexToColorStr colorB;
    };

  # Adjust `color` to contrast against `fixed` by `factor` (0-1).
  adjustContrastAgainstFixed = fixedColor: colorToAdjust: factor:
    w "adjust_contrast" {
      fixed = hexToColorStr fixedColor;
      color = hexToColorStr colorToAdjust;
      inherit factor;
    };

  # Adjust text color to ensure minimum contrast ratio against background.
  ensureTextContrast = textColor: backgroundColor: minRatio:
    w "ensure_contrast" {
      text = norm textColor;
      bg = norm backgroundColor;
      min_ratio = minRatio;
    };

  # =========================================================================
  # Compound helpers (built from primitives)
  # =========================================================================

  matchLightnessSaturation = colorToModify: referenceColor:
    let
      targetL = getOkhslLightness referenceColor;
      targetS = getOkhslSaturation referenceColor;
    in setOkhslSaturation targetS (setOkhslLightness targetL colorToModify);

  invertColorOkhsv = hexColor:
    let currentValue = getOkhsvValue hexColor;
    in setOkhsvValue (1.0 - currentValue) (adjustOkhsvHue 0.5 hexColor);

  # =========================================================================
  # Raw color-string API (for direct high-precision use)
  # =========================================================================

  raw = {
    inherit wasmFile w;
    inherit hexToColorStr colorToHex toOkhsl toOkhsv;
  };
}

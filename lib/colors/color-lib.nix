{ lib ? import <nixpkgs/lib>, }:

let

  # Existing functions (assumed to be defined elsewhere)
  inherit (import ./color-utils.nix { inherit lib; }) convert clamp clampF fmod normHex removeAlpha universal;

  adjustRgb = rgb: adjustFn:
  let
    # Apply adjustFn function to all channels except "a"
    adjustedRgb = builtins.mapAttrs
      (name: value: if name != "a" then adjustFn value else value)
      rgb;
  in
    adjustedRgb;

  # Main color manipulation functions
  colorLib = {
    inherit normHex removeAlpha;

    setLightness = color: lightness:
      let
        hsl = universal.toHsl color;
        light = clampF (lightness / 100.0) 0.0 1.0;

        adjustedHsl = hsl // { l = light; };

      in convert.hslToHex adjustedHsl;

    # Lighten a color by a percentage (0-100)
    lighten = color: percent:
      let
        rgb = universal.toRgb color;
        adjust = channel: clampF ( channel * (percent / 100.0 + 1)) 0.0 1.0;
      in
        convert.rgbToHex (adjustRgb rgb adjust);

    darken = color: percent:
      let
        rgb = universal.toRgb color;
        adjust = channel: clampF ( channel * (1 - percent / 100.0)) 0.0 1.0;
      in
        convert.rgbToHex (adjustRgb rgb adjust);

    invert = color:
      let
        rgb = universal.toRgb color;
        adjust = channel: 1 - channel ;
      in
        convert.rgbToHex (adjustRgb rgb adjust);

    ## Function to shift the hue of a color
    shiftHue = color: shiftAmount:
      let
        hsl = universal.toHsl color;

        # Shift the hue
        newHue = fmod (hsl.h + shiftAmount) 360.0;
        shiftedHsl = hsl // { h = newHue; };

      in convert.hslToHex shiftedHsl;

    ## Adjust the saturation of a color by a percentage (-100 to 100)
    saturate = color: percent:
      let
        hsl = universal.toHsl color;

        # Adjust saturation with clamping
        newSaturation = clampF (hsl.s + (percent / 100.0)) 0.0 1.0;

        adjustedHsl = hsl // { s = newSaturation; };

      in convert.hslToHex adjustedHsl;

    setSaturation = color: saturation:
      let
        hsl = universal.toHsl color;
        s = clampF (saturation / 100.0) 0.0 1.0;

        adjustedHsl = hsl // { inherit s; };

      in convert.hslToHex adjustedHsl;

    mix = color1: color2: percent:
      let
        rgb1 = universal.toRgb color1;
        rgb2 = universal.toRgb color2;

        weight = percent / 100.0;

        adjust = a: b: clampF (a * (1 - weight) + b * weight) 0.0 1.0;

      in convert.rgbToHex {
          r = adjust rgb1.r rgb2.r;
          g = adjust rgb1.g rgb2.g;
          b = adjust rgb1.b rgb2.b;
          a = adjust rgb1.a rgb2.a;
        };

    ## Get the grayscale version of a color
    grayscale = color:
      let
        c = universal.toRgb color;
        gray = clampF (0.299 * c.r + 0.587 * c.g + 0.114 * c.b) 0.0 1.0;
      in convert.rgbToHex { r = gray; g = gray; b = gray; inherit (c) a; };
  };
in colorLib

# color-lib.nix
{ lib ? import <nixpkgs/lib> }:
let
  types = import ./types.nix { };
  math = import ./math.nix { inherit lib; };
  utils = import ./color-utils.nix { inherit lib; };
  hex = import ./formats/hex.nix { inherit utils types; };
  hsl = import ./formats/hsl.nix { inherit math lib types; };
  oklab = import ./formats/oklab.nix { inherit xyz math lib utils types linearRgb; };
  okhsl = import ./formats/okhsl.nix { inherit math utils lib types; };
  oklch = import ./formats/oklch.nix { inherit math utils types; };
  xyz = import ./formats/xyz.nix { inherit math lib utils types linearRgb; };
  linearRgb = import ./formats/linearRgb.nix { inherit math utils types; };
  gammaRgb = import ./formats/gammaRgb.nix { inherit math utils types; };
  okhsv = import ./formats/okhsv.nix { inherit math utils types lib; };

in rec {
  inherit types math utils;
  inherit hex hsl oklab okhsl oklch xyz linearRgb gammaRgb okhsv;

  splitHex = hexStr: types.Hex.check (utils.convert.splitHex hexStr);

  hexStrToRgb = hexStr: hex.ToRgb (splitHex hexStr);
  rgbToHexStr = rgb: utils.convert.combineHex (gammaRgb.ToHex (types.gammaRgb.strictCheck rgb));

  hexStrToOklab = hexStr:
    let
      rgb = hexStrToRgb hexStr;
      linearRgb' = gammaRgb.ToLinear rgb;
      xyz' = linearRgb.ToXyz linearRgb';
    in
      xyz.ToOklab xyz';

  # Convert hex string to OKHSL
  hexStrToOkhsv = hexStr:
    let
      oklab' = hexStrToOklab hexStr;
      oklch' = oklab.ToOklch oklab';
    in
      oklch.ToOkhsv oklch';

  # Convert OKHSL to hex string
  okhsvToHex = okhsv':
    let
      oklch' = okhsv.ToOklch (types.Okhsv.check okhsv');
      oklab' = oklch.ToOklab oklch';
      rgb = oklab.ToRgb oklab';
    in
      rgbToHexStr rgb;

  # Convert hex string to OKHSL
  hexStrToOkhsl = hexStr:
    let
      oklab' = hexStrToOklab hexStr;
      oklch' = oklab.ToOklch oklab';
    in
      oklch.ToOkhsl oklch';

  # Convert OKHSL to hex string
  okhslToHex = okhsl':
    let
      oklch' = okhsl.ToOklch (types.Okhsl.check okhsl');
      oklab' = oklch.ToOklab oklch';
      rgb = oklab.ToRgb oklab';
    in
      rgbToHexStr rgb;


  # Convert OKHSL to hex string
  oklchToHex = oklch':
    let
      oklab' = oklch.ToOklab (types.Oklch.check oklch');
      rgb = oklab.ToRgb oklab';
    in
      rgbToHexStr rgb;

  # Convert hex string to OKHSL
  hexStrToOklch = hexStr:
    let
      oklab' = hexStrToOklab hexStr;
      oklch' = oklab.ToOklch oklab';
    in
      oklch';



  oklchmod = {
    # Set the Hue component to a new value
    setHue = newHue: color:
      let
        color' = types.Oklch.check color;
        clampedHue = math.mod newHue 360;
        newColor = color' // { h = clampedHue; };
      in
        types.Oklch.check newColor;

    # Set the Chroma component to a new value
    setChroma = newChroma: color:
      let
        color' = types.Oklch.check color;
        newColor = color' // { C = math.clamp newChroma 0 1; };
      in
        types.Oklch.check newColor;

    # Set the Lightness component to a new value
    setLightness = newLightness: color:
      let
        color' = types.Oklch.check color;
        newColor = color' // { L = math.clamp newLightness 0 1; };
      in
        types.Oklch.check newColor;

    # Adjust the Hue by a delta value
    adjustHueBy = deltaHue: color:
      let
        color' = types.Oklch.check color;
        newHue = math.mod (color'.h + deltaHue) 360;
        newColor = color' // { h = newHue; };
      in
        types.Oklch.check newColor;

    # Adjust the Chroma by a delta value
    adjustChromaBy = deltaChroma: color:
      let
        color' = types.Oklch.check color;
        newChroma = color'.C + deltaChroma;
        newColor = color' // { C = math.clamp newChroma 0 1; };
      in
        types.Oklch.check newColor;

    # Adjust the Lightness by a delta value
    adjustLightnessBy = deltaLightness: color:
      let
        color' = types.Oklch.check color;
        newLightness = color'.L + deltaLightness;
        newColor = color' // { L = math.clamp newLightness 0 1; };
      in
        types.Oklch.check newColor;

    # Lighten the color by a given percentage
    lighten = percent: color:
      let
        color' = types.Oklch.check color;
        delta = percent / 100.0;
      in
        oklchmod.adjustLightnessBy delta color';

    # Darken the color by a given percentage
    darken = percent: color:
      let
        color' = types.Oklch.check color;
        delta = (-1.0) * percent / 100.0;
      in
        oklchmod.adjustLightnessBy delta color';

    # Mix two colors based on a weight
    mix = colorA: colorB: weight:
      let
        colorA' = types.Oklch.check colorA;
        colorB' = types.Oklch.check colorB;
        w = math.clamp weight 0.0 1.0;
        mixValue = a: b: a * (1.0 - w) + b * w;

        # Calculate the shortest angle difference for Hue mixing
        hueDistance = math.mod (colorB'.h - colorA'.h + 540.0) 360.0 - 180.0;
        newHue = math.mod (colorA'.h + w * hueDistance + 360.0) 360.0;

        # Linearly interpolate Chroma and Lightness
        newChroma = mixValue colorA'.C colorB'.C;
        newLightness = mixValue colorA'.L colorB'.L;

        newColor = { h = newHue; C = newChroma; L = newLightness; };
      in
        types.Oklch.check newColor;

    # Get the complementary color by shifting Hue by 180 degrees
    complement = color:
      let
        color' = types.Oklch.check color;
      in
        oklchmod.adjustHueBy 180.0 color';

    # Invert the color by shifting Hue by 180 degrees and inverting Chroma and Lightness
    invert = color:
      let
        color' = types.Oklch.check color;
        newHue = math.mod (color'.h + 180.0) 360.0;
        newChroma = 1.0 - color'.C;
        newLightness = 1.0 - color'.L;
        newColor = { h = newHue; C = newChroma; L = newLightness; };
      in
        types.Oklch.check newColor;

    # Wrapper function for adjusting OKLCH color with optional parameters
    adjustOklch = { color, hueShift ? 0.0, chromaScale ? 1.0, lightnessScale ? 1.0 }:
      let
        color' = types.Oklch.check color;
        adjustedHue = oklchmod.adjustHueBy hueShift color';
        adjustedChroma = math.clamp (adjustedHue.C * chromaScale) 0.0 1.0;
        adjustedLightness = math.clamp (adjustedHue.L * lightnessScale) 0.0 1.0;
      in
        types.Oklch.check {
          h = adjustedHue.h;
          C = adjustedChroma;
          L = adjustedLightness;
        };
  };


}

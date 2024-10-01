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
in rec {
  inherit types math utils;
  inherit hex hsl oklab okhsl oklch xyz linearRgb gammaRgb;

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

  # Color manipulation functions for OKHSL
  okhslmod = {
    setHue = newHue: color:
      let
        color' = types.Okhsl.check color;
        clampedHue = math.mod newHue 360;
        newColor = color' // { h = clampedHue; };
      in
        types.Okhsl.check newColor;

    setSaturation = newSaturation: color:
      let
        color' = types.Okhsl.check color;
        newColor = color' // { s = math.clamp newSaturation 0 1; };
      in
        types.Okhsl.check newColor;

    setLightness = newLightness: color:
      let
        color' = types.Okhsl.check color;
        newColor = color' // { l = math.clamp newLightness 0 1; };
      in
        types.Okhsl.check newColor;

    adjustHueBy = deltaHue: color:
      let
        color' = types.Okhsl.check color;
        newHue = math.mod (color'.h + deltaHue) 360;
        newColor = color' // { h = newHue; };
      in
        types.Okhsl.check newColor;

    adjustSaturationBy = deltaSaturation: color:
      let
        color' = types.Okhsl.check color;
        newSaturation = color'.s + deltaSaturation;
        newColor = color' // { s = math.clamp newSaturation 0 1; };
      in
        types.Okhsl.check newColor;

    adjustLightnessBy = deltaLightness: color:
      let
        color' = types.Okhsl.check color;
        newLightness = color'.l + deltaLightness;
        newColor = color' // { l = math.clamp newLightness 0 1; };
      in
        types.Okhsl.check newColor;

    lighten = percent: color:
      let
        color' = types.Okhsl.check color;
        delta = percent / 100.0;
      in
        okhslmod.adjustLightnessBy delta color';

    darken = percent: color:
      let
        color' = types.Okhsl.check color;
        delta = (-1.0) * percent / 100.0;
      in
        okhslmod.adjustLightnessBy delta color';

    mix = colorA: colorB: weight:
      let
        colorA' = types.Okhsl.check colorA;
        colorB' = types.Okhsl.check colorB;
        w = math.clamp weight 0.0 1.0;
        mixValue = a: b: a * (1.0 - w) + b * w;
        hueDistance = math.mod (colorB'.h - colorA'.h + 540.0) 360.0 - 180.0;
        newHue = math.mod (colorA'.h + w * hueDistance + 360.0) 360.0;
        newSaturation = mixValue colorA'.s colorB'.s;
        newLightness = mixValue colorA'.l colorB'.l;
        newColor = { h = newHue; s = newSaturation; l = newLightness; };
      in
        types.Okhsl.check newColor;

    complement = color:
      let
        color' = types.Okhsl.check color;
      in
        okhslmod.adjustHueBy 180.0 color';

    invert = color:
      let
        color' = types.Okhsl.check color;
        newHue = math.mod (color'.h + 180.0) 360.0;
        newSaturation = 1.0 - color'.s;
        newLightness = 1.0 - color'.l;
      in
        types.Okhsl.check { h = newHue; s = newSaturation; l = newLightness; };

    # Wrapper function for adjusting OKHSL color
    adjustOkhsl = { color, hueShift ? 0.0, saturationScale ? 1.0, lightnessScale ? 1.0 }:
      let
        color' = types.Okhsl.check color;
        adjustedColor = okhslmod.adjustHueBy hueShift color';
        adjustedSaturation = math.clamp (adjustedColor.s * saturationScale) 0.0 1.0;
        adjustedLightness = math.clamp (adjustedColor.l * lightnessScale) 0.0 1.0;
      in
        types.Okhsl.check {
          h = adjustedColor.h;
          s = adjustedSaturation;
          l = adjustedLightness;
        };
  };

  # Wrapper function to manipulate a hex color
  manipulateHexColor = { hex, hueShift ? 0.0, saturationScale ? 1.0, lightnessScale ? 1.0 }:
    let
      okhsl' = hexStrToOkhsl hex;
      adjustedOkhsl = okhslmod.adjustOkhsl {
        color = okhsl';
        inherit hueShift saturationScale lightnessScale;
      };
    in
      okhslToHex adjustedOkhsl;
}

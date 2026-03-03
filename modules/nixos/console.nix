{
  color-lib,
  theme,
  lib,
  ...
}: let
  inherit (color-lib) setOkhslLightness setOkhslSaturation;
  lighten = setOkhslLightness 0.7;
  saturate = setOkhslSaturation 0.9;

  sa = hex: lighten (saturate hex);
in {
  console.colors = [
    "${theme.dark.base00}" # 0  black
    "${sa theme.dark.base08}" # 1  red (saturated/lightened)
    "${sa theme.dark.base0B}" # 2  green (saturated/lightened)
    "${sa theme.dark.base0A}" # 3  yellow (saturated/lightened)
    "${sa theme.dark.base0D}" # 4  blue (saturated/lightened)
    "${sa theme.dark.base0E}" # 5  magenta (saturated/lightened)
    "${sa theme.dark.base0C}" # 6  cyan (saturated/lightened)
    "${theme.dark.base06}" # 7  white
    "${theme.dark.base03}" # 8  bright black (gray)
    "${theme.dark.base08}" # 9  bright red
    "${theme.dark.base0B}" # 10 bright green
    "${theme.dark.base0A}" # 11 bright yellow
    "${theme.dark.base0D}" # 12 bright blue
    "${theme.dark.base0E}" # 13 bright magenta
    "${theme.dark.base0C}" # 14 bright cyan
    "${theme.dark.base07}" # 15 bright white
  ];
}

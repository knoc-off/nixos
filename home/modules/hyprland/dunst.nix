{ theme, color-lib, ... }:

let
  inherit (color-lib) hexToRgb rgbToHex setOkhslLightness mixColors;

  primary = theme.primary;
  secondary = theme.secondary;
  neutral = theme.neutral;
  accent1 = theme.accent1;
  accent2 = theme.accent2;

in
{
  services.dunst = {
    enable = true;
    settings = {
      global = {
        width = 300;
        height = 300;
        offset = "30x50";
        origin = "top-right";
        corner_radius = 5;
        progress_bar_corner_radius = 5;
        frame_color = theme.base03;
        font = "Droid Sans 9";
      };
      urgency_normal = {
        background = theme.base01;
        foreground = theme.base05;
        highlight = theme.accent1;
        timeout = 10;
      };
      urgency_critical = {
        background = theme.base08;
        foreground = theme.base07;
        highlight = theme.accent2;
        timeout = 0;
      };
    };
  };
}

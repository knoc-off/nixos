{ theme, color-lib, ... }:

let
  inherit (color-lib) hexToRgb rgbToHex setOkhslLightness mixColors;
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
        highlight = theme.base0B;
        timeout = 10;
      };
      urgency_critical = {
        background = theme.base08;
        foreground = theme.base07;
        highlight = theme.base0E;
        timeout = 0;
      };
    };
  };
}

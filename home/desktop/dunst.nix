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
        frame_color = theme.dark.base03;
        font = "Droid Sans 9";
      };
      urgency_normal = {
        background = theme.dark.base01;
        foreground = theme.dark.base05;
        highlight = theme.dark.base0B;
        timeout = 10;
      };
      urgency_critical = {
        background = theme.dark.base08;
        foreground = theme.dark.base07;
        highlight = theme.dark.base0E;
        timeout = 0;
      };
    };
  };
}

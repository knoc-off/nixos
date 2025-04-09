{ theme, color-lib, ... }:

let
  inherit (color-lib) hexToRgb rgbToHex setOkhslLightness mixColors;

  primary = theme.primary;
  secondary = theme.secondary;
  neutral = theme.neutral;
  accent1 = theme.accent1;
  accent2 = theme.accent2;

  setLightness = amount: hex:
    let
      rgb = hexToRgb hex;
      adjusted = setOkhslLightness amount hex;
    in
      adjusted;

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
        frame_color = setLightness 0.3 primary;
        font = "Droid Sans 9";
      };
      urgency_normal = {
        background = setLightness 0.2 primary;
        foreground = setLightness 0.95 neutral;
        highlight = accent1;
        timeout = 10;
      };
      urgency_critical = {
        background = setLightness 0.4 accent2;
        foreground = setLightness 0.95 neutral;
        highlight = accent2;
        timeout = 0;
      };
    };
  };
}

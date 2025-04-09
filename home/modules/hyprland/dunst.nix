{ theme, color-lib, ... }:

let
  inherit (color-lib) hexToRgb rgbToHex adjustOkhslLightness;

  primary = theme.primary;
  secondary = theme.secondary;
  neutral = theme.neutral;
  accent1 = theme.accent1;
  accent2 = theme.accent2;

  lighten = amount: hex:
    let
      rgb = hexToRgb hex;
      adjusted = adjustOkhslLightness amount hex;
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
        frame_color = lighten 0.3 primary;
        font = "Droid Sans 9";
      };
      urgency_normal = {
        background = lighten 0.2 primary;
        foreground = lighten 0.95 neutral;
        highlight = accent1;
        timeout = 10;
      };
      urgency_critical = {
        background = lighten 0.4 accent2;
        foreground = lighten 0.95 neutral;
        highlight = accent2;
        timeout = 0;
      };
    };
  };
}

{ theme, colorLib, ... }:
let
  h2okl = colorLib.hexStrToOklch;
  oklchToHex = colorLib.oklchToHex;
  setLightness = value: color: colorLib.oklchmod.setLightness value color;

  primary = h2okl theme.primary;
  secondary = h2okl theme.secondary;
  neutral = h2okl theme.neutral;
  accent1 = h2okl theme.accent1;
  accent2 = h2okl theme.accent2;
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
        frame_color = oklchToHex (setLightness 0.3 primary);
        font = "Droid Sans 9";
      };
      urgency_normal = {
        background = oklchToHex (setLightness 0.2 primary);
        foreground = oklchToHex (setLightness 0.95 neutral);
        highlight = oklchToHex accent1;
        timeout = 10;
      };
      urgency_critical = {
        background = oklchToHex (setLightness 0.4 accent2);
        foreground = oklchToHex (setLightness 0.95 neutral);
        highlight = oklchToHex accent2;
        timeout = 0;
      };
    };
  };
}

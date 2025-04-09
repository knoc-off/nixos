{ pkgs, config, theme, color-lib, ... }:
let
  # Helper function to set alpha on a hex color string using color-lib
  setAlpha = alphaValue: hexColor:
    let
      rgb = color-lib.hexToRgb hexColor;
      # rgbToHex expects alpha as a float 0.0-1.0
      rgbWithNewAlpha = rgb // { alpha = alphaValue; };
    in
      # Remove the '#' prefix as swaylock expects colors without it for --*-color args
      lib.removePrefix "#" (color-lib.rgbToHex rgbWithNewAlpha);

  swaylock-custom = pkgs.writeShellScriptBin "swaylock-custom" ''
    exec ${config.programs.swaylock.package}/bin/swaylock \
    --layout-bg-color "${theme.base01}" \
    --layout-border-color "${theme.base02}" \
    --layout-text-color "${lib.removePrefix "#" theme.base05}" \
    \
    --line-ver-color "${lib.removePrefix "#" theme.base0D}" \
    --inside-ver-color "${lib.removePrefix "#" theme.base01}" \
    --ring-ver-color "${setAlpha 0.6 theme.base0D}" \
    --text-ver-color "${lib.removePrefix "#" theme.base06}" \
    \
    --line-wrong-color "${lib.removePrefix "#" theme.base08}" \
    --inside-wrong-color "${lib.removePrefix "#" theme.base01}" \
    --ring-wrong-color "${setAlpha 0.6 theme.base08}" \
    --text-wrong-color "${lib.removePrefix "#" theme.base06}" \
    \
    --line-clear-color "${lib.removePrefix "#" theme.base00}" \
    --inside-clear-color "${lib.removePrefix "#" theme.base01}" \
    --ring-clear-color "${lib.removePrefix "#" theme.base0C}" \
    --text-clear-color "${lib.removePrefix "#" theme.base06}" \
    \
    --ring-color "${lib.removePrefix "#" theme.base02}" \
    --key-hl-color "${lib.removePrefix "#" theme.base0C}" \
    --text-color "${lib.removePrefix "#" theme.base05}" \
    \
    --line-color "${lib.removePrefix "#" theme.base00}" \
    --inside-color "${lib.removePrefix "#" theme.base01}" \
    --separator-color "${lib.removePrefix "#" theme.base02}" \
    \
    --indicator-radius "100" \
    --indicator-thickness "1" \
    \
    --clock \
    --datestr "%Y.%m.%d" --timestr "%H:%M:%S" \
    \
    --screenshots \
    --grace $1 \
    --effect-blur "$2" \
    --effect-pixelate "$3" \
    --fade-in $4 \
    --font-size 24 \
    --daemonize
  '';
in {
  services.swayidle.enable = true;

  home.packages = [
    swaylock-custom
  ];

  services.swayidle = {
    events = [
      {
        event = "before-sleep";
        command = "${swaylock-custom}/bin/swaylock-custom 0 50x6 10 0";
      }
      {
        event = "lock";
        command = "lock";
      }
    ];
    timeouts = [
      {
        timeout = 300; # 5 minutes
        command = "${swaylock-custom}/bin/swaylock-custom 5 50x6 10 0.5";
      }
      {
        timeout = 1800; # 30 minutes
        command = "${pkgs.systemd}/bin/systemctl suspend";
      }
    ];
  };
}

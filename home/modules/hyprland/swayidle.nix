{ pkgs, config, theme, colorLib, ... }:
let
  h2okl = colorLib.hexStrToOklch;
  oklchToHex = colorLib.oklchToHex;
  setLightness = value: color: colorLib.oklchmod.setLightness value color;

  primary = h2okl theme.primary;
  secondary = h2okl theme.secondary;
  neutral = h2okl theme.neutral;
  accent1 = h2okl theme.accent1;
  accent2 = h2okl theme.accent2;

  swaylock-custom = pkgs.writeShellScriptBin "swaylock-custom" ''
    exec ${config.programs.swaylock.package}/bin/swaylock \
    --layout-bg-color "${oklchToHex (setLightness 0.2 primary)}" \
    --layout-border-color "${oklchToHex (setLightness 0.3 primary)}" \
    --layout-text-color "${oklchToHex (setLightness 0.8 neutral)}" \
    \
    --line-ver-color "${oklchToHex accent1}" \
    --inside-ver-color "${oklchToHex (setLightness 0.25 primary)}" \
    --ring-ver-color "${oklchToHex (setLightness 0.6 accent1)}" \
    --text-ver-color "${oklchToHex (setLightness 0.95 neutral)}" \
    \
    --line-wrong-color "${oklchToHex accent2}" \
    --inside-wrong-color "${oklchToHex (setLightness 0.3 primary)}" \
    --ring-wrong-color "${oklchToHex (setLightness 0.6 accent2)}" \
    --text-wrong-color "${oklchToHex (setLightness 0.95 neutral)}" \
    \
    --line-clear-color "${oklchToHex (setLightness 0.2 primary)}" \
    --inside-clear-color "${oklchToHex (setLightness 0.3 primary)}" \
    --ring-clear-color "${oklchToHex secondary}" \
    --text-clear-color "${oklchToHex (setLightness 0.95 neutral)}" \
    \
    --ring-color "${oklchToHex (setLightness 0.3 primary)}" \
    --key-hl-color "${oklchToHex secondary}" \
    --text-color "${oklchToHex (setLightness 0.8 neutral)}" \
    \
    --line-color "${oklchToHex (setLightness 0.2 primary)}" \
    --inside-color "${oklchToHex (setLightness 0.25 primary)}" \
    --separator-color "${oklchToHex (setLightness 0.3 primary)}" \
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
        timeout = 300;
        command = "${swaylock-custom}/bin/swaylock-custom 5 50x6 10 0.5";
      }
      {
        timeout = 600;
        command = "${pkgs.systemd}/bin/systemctl suspend";
      }
    ];
  };
}

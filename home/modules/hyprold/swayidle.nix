{
  pkgs,
  config,
  theme,
  ...
}: let
  swaylock-custom = pkgs.writeShellScriptBin "swaylock-custom" ''
    exec ${config.programs.swaylock.package}/bin/swaylock \
    --layout-bg-color "${theme.base00}" \
    --layout-border-color "${theme.base02}" \
    --layout-text-color "${theme.base05}" \
    \
    --line-ver-color "${theme.green00}" \
    --inside-ver-color "${theme.base03}" \
    --ring-ver-color "${theme.green01}" \
    --text-ver-color "${theme.white00}" \
    \
    --line-wrong-color "${theme.red00}" \
    --inside-wrong-color "${theme.base02}" \
    --ring-wrong-color "${theme.red01}" \
    --text-wrong-color "${theme.white00}" \
    \
    --line-clear-color "${theme.base00}" \
    --inside-clear-color "${theme.base02}" \
    --ring-clear-color "${theme.yellow00}" \
    --text-clear-color "${theme.white00}" \
    \
    --ring-color "${theme.base02}" \
    --key-hl-color "${theme.base0B}" \
    --text-color "${theme.base05}" \
    \
    --line-color "${theme.base00}" \
    --inside-color "${theme.base01}" \
    --separator-color "${theme.base02}" \
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

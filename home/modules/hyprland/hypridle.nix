{ pkgs, config, theme, colorLib, ... }:
let
  setAlpha = colorLib.hexStrSetAlpha;

  swaylock-custom = pkgs.writeShellScriptBin "swaylock-custom" ''
    exec ${config.programs.swaylock.package}/bin/swaylock \
    --layout-bg-color "${theme.base01}" \
    --layout-border-color "${theme.base02}" \
    --layout-text-color "${theme.base05}" \
    \
    --line-ver-color "${theme.base0D}" \
    --inside-ver-color "${theme.base01}" \
    --ring-ver-color "${setAlpha 0.6 theme.base0D}" \
    --text-ver-color "${theme.base06}" \
    \
    --line-wrong-color "${theme.base08}" \
    --inside-wrong-color "${theme.base01}" \
    --ring-wrong-color "${setAlpha 0.6 theme.base08}" \
    --text-wrong-color "${theme.base06}" \
    \
    --line-clear-color "${theme.base00}" \
    --inside-clear-color "${theme.base01}" \
    --ring-clear-color "${theme.base0C}" \
    --text-clear-color "${theme.base06}" \
    \
    --ring-color "${theme.base02}" \
    --key-hl-color "${theme.base0C}" \
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
  services.hypridle = {
    enable = true;
    package = pkgs.hypridle;

    settings = {
      general = {
        # This is equivalent to the before-sleep event
        before_sleep_cmd = "${swaylock-custom}/bin/swaylock-custom 0 50x6 10 0";
        after_sleep_cmd = ""; # Optional: Add a command to run after waking from sleep
        lock_cmd = "${swaylock-custom}/bin/swaylock-custom 0 50x6 10 0"; # For the lock event
      };

      listener = [
        # First timeout (5 minutes)
        {
          timeout = 300;
          on-timeout = "${swaylock-custom}/bin/swaylock-custom 5 50x6 10 0.5";
        }
        # Second timeout (30 minutes)
        {
          timeout = 1800;
          on-timeout = "${pkgs.systemd}/bin/systemctl suspend";
        }
      ];
    };
  };

  home.packages = [
    swaylock-custom
  ];
}


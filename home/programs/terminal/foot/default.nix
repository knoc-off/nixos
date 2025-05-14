{ pkgs, lib, config, theme, color-lib, ... }:
let
  # Define lighten and saturate based on your color-lib
  lighten = color-lib.setOkhslLightness 0.7;
  saturate = color-lib.setOkhslSaturation 0.9;
  sa = Hex: (lighten (saturate Hex));
in
{
  programs.foot = {
    enable = true;
    settings = {
      main = {
        term = "xterm-256color";
        font = "FiraCode Nerd Font Mono:size=15";
        dpi-aware = "no";
        pad = "0x0";
      };

      colors = {
        background = theme.base00;
        foreground = theme.base06;

        # Regular ANSI colors
        regular0 = theme.base00;
        regular1 = theme.base08;
        regular2 = theme.base0B;
        regular3 = theme.base0A;
        regular4 = theme.base0D;
        regular5 = theme.base0E;
        regular6 = theme.base0C;
        regular7 = theme.base06;

        # Bright ANSI colors
        bright0 = theme.base03;
        bright1 = sa theme.base08;
        bright2 = sa theme.base0B;
        bright3 = sa theme.base0A;
        bright4 = sa theme.base0D;
        bright5 = sa theme.base0E;
        bright6 = sa theme.base0C;
        bright7 = theme.base07;

        selection-background = theme.base02;
        selection-foreground = theme.base06; # Matching main foreground
        urls = theme.base0C;
        flash = theme.base08;
      };

      cursor = {
        # Format: "foreground-on-cursor-block cursor-block-background"
        color = "${theme.base00} ${theme.base05}";
      };

      bell = {
        visual = "no";
      };

      mouse = {
        hide-when-typing = "no";
      };

      "key-bindings" = {
        "spawn-terminal" = "Control+t";
      };

      scrollback = {
        multiplier = "3.0"; # Default is 3.0, adjust as needed
      };
    };
  };
}


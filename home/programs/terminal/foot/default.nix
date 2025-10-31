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
        background = theme.dark.base00;
        foreground = theme.dark.base06;

        # Regular ANSI colors
        regular0 = theme.dark.base00;
        regular1 = theme.dark.base08;
        regular2 = theme.dark.base0B;
        regular3 = theme.dark.base0A;
        regular4 = theme.dark.base0D;
        regular5 = theme.dark.base0E;
        regular6 = theme.dark.base0C;
        regular7 = theme.dark.base06;

        # Bright ANSI colors
        bright0 = theme.dark.base03;
        bright1 = sa theme.dark.base08;
        bright2 = sa theme.dark.base0B;
        bright3 = sa theme.dark.base0A;
        bright4 = sa theme.dark.base0D;
        bright5 = sa theme.dark.base0E;
        bright6 = sa theme.dark.base0C;
        bright7 = theme.dark.base07;

        selection-background = theme.dark.base02;
        selection-foreground = theme.dark.base06; # Matching main foreground
        urls = theme.dark.base0C;
        flash = theme.dark.base08;
      };

      cursor = {
        # Format: "foreground-on-cursor-block cursor-block-background"
        color = "${theme.dark.base00} ${theme.dark.base05}";
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


{
  color-lib,
  theme,
  lib,
  pkgs,
  ...
}: let
  inherit (color-lib) setOkhslLightness setOkhslSaturation;
  lighten = setOkhslLightness 0.7;
  saturate = setOkhslSaturation 0.9;

  sa = hex: lighten (saturate hex);
in {
  home.sessionVariables = {
    TERMINAL = "ghostty";
  };

  programs.ghostty = {
    enable = true;

    enableZshIntegration = true;

    settings = {
      font-family = "FiraCode Nerd Font Mono";
      font-size = 15;

      window-padding-x = 2;
      window-padding-y = 2;

      command = ""; # Disable bell command

      focus-follows-mouse = true;

      palette = [
        "0=#${theme.dark.base00}" # black
        "1=#${sa theme.dark.base08}" # red (saturated/lightened)
        "2=#${sa theme.dark.base0B}" # green (saturated/lightened)
        "3=#${sa theme.dark.base0A}" # yellow (saturated/lightened)
        "4=#${sa theme.dark.base0D}" # blue (saturated/lightened)
        "5=#${sa theme.dark.base0E}" # magenta (saturated/lightened)
        "6=#${sa theme.dark.base0C}" # cyan (saturated/lightened)
        "7=#${theme.dark.base06}" # white
        "8=#${theme.dark.base03}" # bright black (gray)
        "9=#${theme.dark.base08}" # bright red
        "10=#${theme.dark.base0B}" # bright green
        "11=#${theme.dark.base0A}" # bright yellow
        "12=#${theme.dark.base0D}" # bright blue
        "13=#${theme.dark.base0E}" # bright magenta
        "14=#${theme.dark.base0C}" # bright cyan
        "15=#${theme.dark.base07}" # bright white
      ];

      background = "${theme.dark.base00}";
      foreground = "${theme.dark.base06}";

      cursor-color = "${theme.dark.base09}";
      cursor-style = "bar";
      cursor-style-blink = false;
      adjust-cursor-thickness = "200%";

      selection-background = "${theme.dark.base02}";
      selection-foreground = "${theme.dark.base06}";

      keybind = let
        isLinux = pkgs.stdenv.isLinux;
        isDarwin = pkgs.stdenv.isDarwin;
      in
        [
          "clear"
          "super+c=copy_to_clipboard"
          "super+v=paste_from_clipboard"
          "super+a=select_all"
          "super+q=quit"
        ]
        ++ lib.optionals isLinux [
          "super+t=new_window"
          "super+shift+t=new_tab"
        ]
        ++ lib.optionals isDarwin [
          "super+t=new_tab"
          "super+shift+t=new_window"
        ]
        ++ [
          "super+w=close_surface"

          "super+one=goto_tab:1"
          "super+two=goto_tab:2"
          "super+three=goto_tab:3"
          "super+four=goto_tab:4"
          "super+five=goto_tab:5"
          "super+six=goto_tab:6"
          "super+seven=goto_tab:7"
          "super+eight=goto_tab:8"
          "super+nine=goto_tab:9"

          "super+equal=increase_font_size:1"
          "super+minus=decrease_font_size:1"
          "super+zero=reset_font_size"

          "super+shift+enter=new_split:right"
          "super+shift+w=close_surface"

          "super+h=goto_split:left"
          "super+j=goto_split:bottom"
          "super+k=goto_split:top"
          "super+l=goto_split:right"

          "super+ctrl+h=resize_split:left,10"
          "super+ctrl+j=resize_split:down,10"
          "super+ctrl+k=resize_split:up,10"
          "super+ctrl+l=resize_split:right,10"
        ];
    };
  };
}

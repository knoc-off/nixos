{ color-lib, theme, lib, ... }:
let
  inherit (color-lib) setOkhslLightness setOkhslSaturation;
  lighten = setOkhslLightness 0.6;
  saturate = setOkhslSaturation 0.8;

  sa = hex: lighten ( saturate hex);

in
{
  imports = [ ./tab_bar.nix ];

  home.sessionVariables = {
    TERMINAL = "kitty";
  };

  programs.kitty = {
    enable = true;
    font = {
      name = "FiraCode Nerd Font Mono";
      size = 15;
    };
    shellIntegration.enableZshIntegration = true;
    keybindings = {
      "ctrl+t" = "new_os_window_with_cwd";
      "ctrl+shift+t" = "new_window_with_cwd";
      "ctrl+l" = "clear_terminal to_cursor active";
    };
    extraConfig = ''
      touch_scroll_multiplier 6.5
      allow_remote_control socket
      listen_on unix:/tmp/kitty-{kitty_pid}.socket

      mouse_map right press ungrabbed mouse_select_command_output
    '';

    settings = rec {
      tab_bar_style = "custom";
      tab_bar_margin_height = "0.0 0.0";
      tab_title_template =
        " {index}: {f'{title[:6]}-{title[-6:]}' if title.rindex(title[-1]) + 1 > 13 else title.center(7)} ";
      allow_remote_control = "yes";

      enable_audio_bell = "no";
      visual_bell_duration = "0.0";

      focus_follows_mouse = "yes";

      # base16 colors
      color0 = "#${theme.base00}"; # black
      color1 = "#${theme.base08}"; # red
      color2 = "#${theme.base0B}"; # green
      color3 = "#${theme.base0A}"; # Yellow
      color4 = "#${theme.base0D}"; # Blue
      color5 = "#${theme.base0E}"; # Magenta
      color6 = "#${theme.base0C}"; # Cyan
      color7 = "#${theme.base05}"; # White

      # Bright colors adjusted for more lightness and saturation
      color8 = "#${ sa theme.base03}"; # Bright Black (Gray)
      color9 = "#${ sa theme.base08}"; # Bright Red
      color10 = "#${sa theme.base0B}"; # Bright Green
      color11 = "#${sa theme.base0A}"; # Bright Yellow
      color12 = "#${sa theme.base0D}"; # Bright Blue
      color13 = "#${sa theme.base0E}"; # Bright Magenta
      color14 = "#${sa theme.base0C}"; # Bright Cyan
      color15 = "#${sa theme.base07}"; # Bright White

      # Derived colors
      foreground = "#${theme.base06}";
      background = "#${theme.base00}"; # Use base00 directly
      selection_background = "#${theme.base02}"; # Use base02 (Dark Selection Background)
      selection_foreground = "none";
      url_color = "#${theme.base0C}";
      cursor = "#${theme.base05}";

      active_border_color = "#${theme.base0D}";
      inactive_border_color = "#${theme.base03}";
      active_tab_background = "#${theme.base01}"; # Use base01 (Dark Background highlight)
      active_tab_foreground = "#${theme.base07}";
      inactive_tab_background = "#${theme.base00}";
      inactive_tab_foreground = "#${theme.base05}";
      tab_bar_background = "#${theme.base00}";

      visual_bell_color = "#${theme.base08}";

      mark1_foreground = "#${theme.base00}";
      mark1_background = "#${theme.base0C}";
      mark2_foreground = "#${theme.base00}";
      mark2_background = "#${theme.base0D}";
      mark3_foreground = "#${theme.base00}";
      mark3_background = "#${theme.base0E}";

      window_padding_width = 0;
    };
  };
}

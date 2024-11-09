{ colorLib, theme, ... }: let
  sl = l: hex: oklchToHex (colorLib.oklchmod.setLightness l (colorLib.hexStrToOklch hex));
  sc = c: hex: oklchToHex (colorLib.oklchmod.setChroma c (colorLib.hexStrToOklch hex));
  mix = hex1: hex2: w: oklchToHex (colorLib.oklchmod.mix (colorLib.hexStrToOklch hex1) (colorLib.hexStrToOklch hex2) w);
  sh = deg: hex: oklchToHex (colorLib.oklchmod.adjustHueBy deg (colorLib.hexStrToOklch hex));
  oklchToHex = colorLib.oklchToHex;

in {
  imports = [./tab_bar.nix];

  programs.kitty = {
    enable = true;
    font = {
      name = "FiraCode Nerd Font Mono";
      size = 15;
    };
    shellIntegration.enableZshIntegration = false;
    keybindings = {
      "ctrl+t" = "new_os_window_with_cwd";
      "ctrl+shift+t" = "new_window_with_cwd";
      "ctrl+l" = "clear_terminal to_cursor active";
      "shift+enter" = "send_key alt+enter";
    };
    extraConfig = ''
      touch_scroll_multiplier 3.0
      allow_remote_control socket
      listen_on unix:/tmp/kitty-{kitty_pid}.socket

      mouse_map right press ungrabbed mouse_select_command_output
    '';
    settings = rec {
      tab_bar_style = "custom";
      tab_bar_margin_height = "0.0 0.0";
      tab_title_template = " {index}: {f'{title[:6]}-{title[-6:]}' if title.rindex(title[-1]) + 1 > 13 else title.center(7)} ";
      allow_remote_control = "yes";

      enable_audio_bell = "no";
      visual_bell_duration = "0.0";

      focus_follows_mouse = "yes";

      # base16 colors
      color0 = theme.base00;  # black
      color1 = theme.base08;  # red
      color2 = theme.base0B;  # green
      color3 = theme.base0A;  # Yellow
      color4 = theme.base0D;  # Blue
      color5 = theme.base0E;  # Magenta
      color6 = theme.base0C;  # Cyan
      color7 = theme.base05;  # White

      color8 = theme.base03;   # Bright Black (Gray)
      color9 = theme.base08;   # Bright Red
      color10 = theme.base0B;  # Bright Green
      color11 = theme.base0A;  # Bright Yellow
      color12 = theme.base0D;  # Bright Blue
      color13 = theme.base0E;  # Bright Magenta
      color14 = theme.base0C;  # Bright Cyan
      color15 = theme.base07;  # Bright White

      # Derived colors
      foreground = theme.base05;
      background = "#${sl 0.2 theme.base00}";
      selection_background = "#${sc 0.2 (sl 0.6 theme.base0D)}";
      selection_foreground = "none";
      url_color = theme.base0C;
      cursor = theme.base05;

      active_border_color = theme.base0D;
      inactive_border_color = theme.base03;
      active_tab_background = "#${sl 0.3 theme.base0D}";
      active_tab_foreground = theme.base07;
      inactive_tab_background = theme.base00;
      inactive_tab_foreground = theme.base05;
      tab_bar_background = theme.base00;

      visual_bell_color = theme.base08;

      mark1_foreground = theme.base00;
      mark1_background = theme.base0C;
      mark2_foreground = theme.base00;
      mark2_background = theme.base0D;
      mark3_foreground = theme.base00;
      mark3_background = theme.base0E;

      window_padding_width = 0;
    };
  };
}

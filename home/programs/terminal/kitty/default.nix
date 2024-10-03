{ colorLib, ... }: let
  sl = l: hex: oklchToHex ( colorLib.oklchmod.setLightness l (colorLib.hexStrToOklch hex));
  sc = c: hex: oklchToHex ( colorLib.oklchmod.setChroma c (colorLib.hexStrToOklch hex));
  mix = hex1: hex2: w: oklchToHex ( colorLib.oklchmod.mix (colorLib.hexStrToOklch hex1) (colorLib.hexStrToOklch hex2) w);
  sh = deg: hex: oklchToHex ( colorLib.oklchmod.adjustHueBy deg (colorLib.hexStrToOklch hex));
  oklchToHex = colorLib.oklchToHex;

  primaryColor = "#268bd2";

  # Function to create a pastel color with specified lightness and chroma
  makePrettyPastel = color:
    let
      basePastel = sl 0.70 (sc 0.155 color);
    in
      basePastel;

  # Function to create a light variant
  makeLightVariant = color:
    let
      lighterColor = sl 0.90 color;
      slightlyShifted = sh 1 lighterColor;
    in
      sc 0.25 slightlyShifted;

  # Base colors
  baseColors = {
    black = "#000000";
    red = "#800000";
    green = "#008000";
    yellow = "#808000";
    blue = "#000080";
    magenta = "#800080";
    cyan = "#008080";
    white = "#c0c0c0";
  };

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
    '';
    settings = rec {
      tab_bar_style = "custom";
      tab_bar_margin_height = "0.0 0.0";
      tab_title_template = " {index}: {f'{title[:6]}…{title[-6:]}' if title.rindex(title[-1]) + 1 > 13 else title.center(7)} ";

      enable_audio_bell = "no";
      visual_bell_duration = "0.0";

      # Basic 16 colors
      color0 = "#${sl 0.15 baseColors.black}";  # Black
      color8 = "#${sl 0.35 baseColors.black}";  # Bright Black (Gray)

      color1 = "#${makePrettyPastel baseColors.red}";
      color9 = "#${makeLightVariant color1}";

      color2 = "#${makePrettyPastel baseColors.green}";  # Green
      color10 = "#${makeLightVariant color2}";  # Bright Green

      color3 = "#${makePrettyPastel baseColors.yellow}";  # Yellow
      color11 = "#${makeLightVariant color3}";  # Bright Yellow

      color4 = "#${makePrettyPastel baseColors.blue}";  # Blue
      color12 = "#${makeLightVariant color4}";  # Bright Blue

      color5 = "#${makePrettyPastel baseColors.magenta}";  # Magenta
      color13 = "#${makeLightVariant color5}";  # Bright Magenta

      color6 = "#${makePrettyPastel baseColors.cyan}";  # Cyan
      color14 = "#${makeLightVariant color6}";  # Bright Cyan

      color7 = "#${sl 0.85 baseColors.white}";  # White
      color15 = "#${sl 0.95 baseColors.white}";  # Bright White

      # Derived colors
      foreground = color7;
      background = "#${sc 0.01 (sl 0.2 primaryColor)}";
      selection_background = "#${sc 0.02 (sl 0.4 color4)}";
      selection_foreground = "none";
      url_color = color6;
      cursor = color15;

      active_border_color = color4;
      inactive_border_color = color8;
      active_tab_background = "#${sl 0.3 color4}";
      active_tab_foreground = color15;
      inactive_tab_background = color0;
      inactive_tab_foreground = color7;
      tab_bar_background = color0;

      visual_bell_color = color1;

      mark1_foreground = color0;
      mark1_background = color6;
      mark2_foreground = color0;
      mark2_background = color4;
      mark3_foreground = color0;
      mark3_background = color5;

      window_padding_width = 0;
    };
  };
}

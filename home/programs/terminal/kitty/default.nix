{ colorLib, ... }: let
  ra = x: colorLib.removeAlpha x;
  sl = colorLib.setLightness;
  ss = colorLib.setSaturation;
  mix = colorLib.mix;
  sh = colorLib.shiftHue;
  #primaryColor = "#005ebc";
  primaryColor = "#268bd2";

  # Function to create a pretty pastel color
  makePrettyPastel = color:
    let
      basePastel = ra (sl (ss color 80) 70);
      withPrimaryInfluence = mix basePastel primaryColor 15;
    in
      ra (sl (ss withPrimaryInfluence 90) 70);

  # Function to create a light variant
  makeLightVariant = color:
    let
      lighterColor = ra (sl color 80);
      slightlyShifted = sh lighterColor 5;
    in
      ra (ss slightlyShifted 90);

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
      color0 = "#${ra (sl baseColors.black 15)}";  # Black
      color8 = "#${ra (sl baseColors.black 35)}";  # Bright Black (Gray)

      color1 = "#${makePrettyPastel baseColors.red}";  # Red
      color9 = "#${makeLightVariant color1}";  # Bright Red

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

      color7 = "#${ra (sl baseColors.white 85)}";  # White
      color15 = "#${ra (sl baseColors.white 95)}";  # Bright White

      # Derived colors
      foreground = color7;
      background = "#${ra (sl ( mix color0 primaryColor 10 ) 10)}";
      selection_background = color4;
      selection_foreground = color15;
      url_color = color6;
      cursor = color15;

      active_border_color = color4;
      inactive_border_color = color8;
      active_tab_background = "#${ra (sl color4 30)}";
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

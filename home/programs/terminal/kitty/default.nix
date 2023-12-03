{ pkgs, config, theme, lib, ... }:
{
  imports = [ ./tab_bar.nix ];

  programs.kitty = {
    enable = true;
    font = {
      name = "FiraCode"; #config.fontProfiles.monospace.family;# Smart
      size = 15;
    };
    keybindings = {
      "ctrl+t" = "launch --cwd=current --type os-window";
      "ctrl+l" =  "clear_terminal to_cursor active";
      #"ctrl+c" =  "copy_or_interrupt";
    };
    settings = {
      tab_bar_style = "custom";
      tab_bar_margin_height = "0.0 0.0";
      tab_title_template = " {index}: {f'{title[:6]}…{title[-6:]}' if title.rindex(title[-1]) + 1 > 13 else title.center(7)} ";

      window_padding_width = 0;
      foreground = "#${theme.base06}";
      background = "#${theme.base01}";
      selection_background = "#${theme.base02}";
      selection_foreground = "none";
      url_color = "#${theme.blue00}";
      cursor = "#${theme.base06}";
      #cursor_text_color = "none";
      active_border_color = "#${theme.base03}";
      inactive_border_color = "#${theme.base01}";
      active_tab_background = "#${theme.base02}";
      active_tab_foreground = "#${theme.base0D}";
      inactive_tab_background = "#${theme.base01}";
      inactive_tab_foreground = "#${theme.base05}";
      tab_bar_background = "#${theme.base03}";
      # Each of the theme below is paired with a light + dark varient
      # might need to invert order.
      ## Black
      color0 = "#${theme.base00}";
      color8 = "#${theme.base01}";

      # Red
      color1 = "#${theme.red00}";
      color9 = "#${theme.red01}";

      # green
      color2 = "#${theme.green00}";
      color10 = "#${theme.green01}";

      # Yellow
      color3 = "#${theme.yellow00}";
      color11 = "#${theme.yellow01}";

      # Blue
      color4 = "#${theme.blue00}";
      color12 = "#${theme.blue01}";

      # Magenta
      color5 = "#${theme.purple00}";
      color13 = "#${theme.purple01}";

      # Cyan
      color6 = "#${theme.cyan00}";
      color14 = "#${theme.cyan01}";

      # White
      color7 = "#${theme.white00}";
      color15 = "#${theme.white01}";

      mark1_foreground = "#${theme.base08}";
      mark1_background = "#${theme.blue00}"; # light blue
      mark2_foreground = "#${theme.base0A}";
      mark2_background = "#${theme.orange00}"; # Beige
      mark3_foreground = "#${theme.base0B}";
      mark3_background = "#${theme.base0E}"; # Violet

      # IDK:
      color16 = "#${theme.horriblepink}";
      color17 = "#${theme.horriblepink}";
      color18 = "#${theme.horriblepink}";
      color19 = "#${theme.horriblepink}";
      color20 = "#${theme.horriblepink}";
      color21 = "#${theme.horriblepink}";
    };
  };
}

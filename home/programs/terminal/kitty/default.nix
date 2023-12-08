{ pkgs, config, theme, lib, ... }:
let
  isValidColor = thing:
    if builtins.isString thing then
      (builtins.match "^[0-9a-fA-F]{6}" thing) != null
    else
      false;


  withHashtag = theme // (builtins.mapAttrs (_: value: if isValidColor value then "#" + value else value) theme);
in
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
      "ctrl+l" = "clear_terminal to_cursor active";
      #"ctrl+c" =  "copy_or_interrupt";
    };
    settings = {
      tab_bar_style = "custom";
      tab_bar_margin_height = "0.0 0.0";
      tab_title_template = " {index}: {f'{title[:6]}…{title[-6:]}' if title.rindex(title[-1]) + 1 > 13 else title.center(7)} ";

      window_padding_width = 0;
      foreground = "${withHashtag.base06}";
      background = "${withHashtag.base01}";
      selection_background = "${withHashtag.base02}";
      selection_foreground = "none";
      url_color = "${withHashtag.blue00}";
      cursor = "${withHashtag.base06}";
      #cursor_text_color = "none";
      active_border_color = "${withHashtag.base03}";
      inactive_border_color = "${withHashtag.base01}";
      active_tab_background = "${withHashtag.base02}";
      active_tab_foreground = "${withHashtag.base0D}";
      inactive_tab_background = "${withHashtag.base01}";
      inactive_tab_foreground = "${withHashtag.base05}";
      tab_bar_background = "${withHashtag.base03}";
      # Each of the withHashtag below is paired with a light + dark varient
      # might need to invert order.
      ## Black
      color0 = "${withHashtag.base00}";
      color8 = "${withHashtag.base01}";

      # Red
      color1 = "${withHashtag.red00}";
      color9 = "${withHashtag.red01}";

      # green
      color2 = "${withHashtag.green00}";
      color10 = "${withHashtag.green01}";

      # Yellow
      color3 = "${withHashtag.yellow00}";
      color11 = "${withHashtag.yellow01}";

      # Blue
      color4 = "${withHashtag.blue00}";
      color12 = "${withHashtag.blue01}";

      # Magenta
      color5 = "${withHashtag.purple00}";
      color13 = "${withHashtag.purple01}";

      # Cyan
      color6 = "${withHashtag.cyan00}";
      color14 = "${withHashtag.cyan01}";

      # White
      color7 = "${withHashtag.white00}";
      color15 = "${withHashtag.white01}";

      mark1_foreground = "${withHashtag.base08}";
      mark1_background = "${withHashtag.blue00}"; # light blue
      mark2_foreground = "${withHashtag.base0A}";
      mark2_background = "${withHashtag.orange00}"; # Beige
      mark3_foreground = "${withHashtag.base0B}";
      mark3_background = "${withHashtag.base0E}"; # Violet

      # IDK:
      color16 = "${withHashtag.hp}";
      color17 = "${withHashtag.hp}";
      color18 = "${withHashtag.hp}";
      color19 = "${withHashtag.hp}";
      color20 = "${withHashtag.hp}";
      color21 = "${withHashtag.hp}";
    };
  };
}

{
  theme,
  ...
}: let
  isValidColor = thing:
    if builtins.isString thing
    then (builtins.match "^[0-9a-fA-F]{6}" thing) != null
    else false;
  withHashtag =
    theme
    // (builtins.mapAttrs (_: value:
      if isValidColor value
      then "#" + value
      else value)
    theme);
in {
  imports = [./tab_bar.nix];

  programs.kitty = {
    enable = true;
    font = {
      name = "FiraCode Nerd Font Mono"; #config.fonts.fontconfig.defaultFonts.monospace; # Smart
      size = 15;
    };
    shellIntegration.enableZshIntegration = true;
    keybindings = {
      "ctrl+t" = "launch --cwd=current --type os-window";
      "ctrl+l" = "clear_terminal to_cursor active";
      #"ctrl+c" =  "copy_or_interrupt";
    };
    extraConfig = ''
      touch_scroll_multiplier 3.0
    '';
    settings = {
      tab_bar_style = "custom";
      tab_bar_margin_height = "0.0 0.0";
      tab_title_template = " {index}: {f'{title[:6]}…{title[-6:]}' if title.rindex(title[-1]) + 1 > 13 else title.center(7)} ";

      enable_audio_bell = "no";
      visual_bell_duration = "0.0"; # annoying too
      visual_bell_color = "${withHashtag.base01}"; #"none";

      #window_resize_step_cells = 2;
      #window_resize_step_lines = 2;

      window_padding_width = 0;
      foreground = "${withHashtag.base06}";
      background = "${withHashtag.base01}";
      selection_background = "${withHashtag.base03}";
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
      color8 = "${withHashtag.base04}";

      # Red
      color1 = "${withHashtag.red01}";
      color9 = "${withHashtag.red02}";

      # green
      color2 = "${withHashtag.green01}";
      color10 = "${withHashtag.green02}";

      # Yellow
      color3 = "${withHashtag.yellow00}";
      color11 = "${withHashtag.yellow01}";

      # Blue
      color4 = "${withHashtag.blue01}";
      color12 = "${withHashtag.blue02}";

      # Magenta
      color5 = "${withHashtag.purple00}";
      color13 = "${withHashtag.purple01}";

      # Cyan
      color6 = "${withHashtag.cyan02}";
      color14 = "${withHashtag.cyan03}";

      # White
      color7 = "${withHashtag.white00}";
      color15 = "${withHashtag.white01}";

      mark1_foreground = "${withHashtag.idk00}";
      mark1_background = "${withHashtag.idk01}"; # light blue
      mark2_foreground = "${withHashtag.idk02}";
      mark2_background = "${withHashtag.idk03}"; # Beige
      mark3_foreground = "${withHashtag.idk04}";
      mark3_background = "${withHashtag.idk05}"; # Violet

      # can change all the colors with the following format, xx is between 0..255
      # colorXX = "${withHashtag.idk01}";
    };
  };
}

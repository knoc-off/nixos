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
  imports = [./tab_bar.nix];

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
      "ctrl+shift+r" = "set_tab_title";
      "cmd+r" = "set_tab_title";

      "ctrl+t" = "new_os_window_with_cwd";
      "ctrl+shift+t" = "new_window_with_cwd";
      "ctrl+l" = "clear_terminal to_cursor active";

      # swap window for master
      "cmd+enter" = "move_window_to_top";
      "shift+enter" = "move_window_to_top";
      "alt+enter" = "launch --location=split";
    };
    extraConfig = ''


        allow_remote_control socket
        listen_on unix:/tmp/kitty-{kitty_pid}.socket

        mouse_map right press ungrabbed mouse_select_command_output

        # tall layout
        enabled_layouts tall:bias=60;full_size=1;mirrored=false

        # You may need to set macos_option_as_alt to 'yes' for this to work as expected
        macos_option_as_alt yes

        # Switch focus using Option + Arrow Keys
        map alt+left  neighboring_window left
        map alt+right neighboring_window right
        map alt+up    neighboring_window up
        map alt+down  neighboring_window down

        # Switch focus using Option + hjkl
        map alt+h neighboring_window left
        map alt+l neighboring_window right
        map alt+k neighboring_window up
        map alt+j neighboring_window down


      ${ # tag:hardwarespecific
        if pkgs.stdenv.isDarwin
        then ''
          touch_scroll_multiplier 1
        ''
        else ''
          touch_scroll_multiplier 6.5
        ''
      }


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
      color0 = "#${theme.base00}"; # black
      color1 = "#${sa theme.base08}"; # red
      color2 = "#${sa theme.base0B}"; # green
      color3 = "#${sa theme.base0A}"; # Yellow
      color4 = "#${sa theme.base0D}"; # Blue
      color5 = "#${sa theme.base0E}"; # Magenta
      color6 = "#${sa theme.base0C}"; # Cyan
      color7 = "#${theme.base06}"; # White

      # Bright colors adjusted for more lightness and saturation
      color8 = "#${theme.base03}"; # Bright Black (Gray)
      color9 = "#${theme.base08}"; # Bright Red
      color10 = "#${theme.base0B}"; # Bright Green
      color11 = "#${theme.base0A}"; # Bright Yellow
      color12 = "#${theme.base0D}"; # Bright Blue
      color13 = "#${theme.base0E}"; # Bright Magenta
      color14 = "#${theme.base0C}"; # Bright Cyan
      color15 = "#${theme.base07}"; # Bright White

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

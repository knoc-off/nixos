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
  home.packages = [
    (pkgs.writeShellScriptBin "kitty-debug-window" ''
      ${pkgs.kitty}/bin/kitten @ ls | ${pkgs.jq}/bin/jq
      read -n 1
    '')
  ];

  programs.kitty = {
    enable = true;
    font = {
      name = "FiraCode Nerd Font Mono";
      size = 15;
    };
    shellIntegration.enableZshIntegration = true;
    keybindings =
      {
        "ctrl+shift+r" = "set_tab_title";
        "ctrl+shift+t" = "new_window_with_cwd";
        "ctrl+l" = "clear_terminal to_cursor active";

        # swap window for master
        "super+backslash" = "move_window_to_top"; # overrides

        # Spawn new split, with cwd.
        "alt+enter" = "launch --location=split --cwd=current";

        "super+c" = "copy_to_clipboard";
        "super+v" = "paste_from_clipboard";
        "super+a" = "select_all";
        "super+f" = "show_scrollback";
        "super+t" = "new_tab_with_cwd";
        "super+w" = "close_tab";
        # "super+n" = "new_os_window";
        "super+z" = "undo";
        "super+shift+z" = "redo";
      }
      // lib.optionalAttrs pkgs.stdenv.isDarwin {
        # "cmd+r" = "set_tab_title";
        # "ctrl+t" = "launch --type=os-window --cwd=current";
        # "super+n" = "launch --type=os-window";
        # "cmd+enter" = "move_window_to_top";
      }
      // lib.optionalAttrs (!pkgs.stdenv.isDarwin) {
        "ctrl+t" = "new_os_window_with_cwd";
      };
    extraConfig = ''

        # this is so that hyprland can control kitty:
        allow_remote_control socket
        listen_on unix:/tmp/kitty-{kitty_pid}.socket


        # this may be interesting to map to a keybind?
        mouse_map right press ungrabbed mouse_select_command_output

        # add a keybind to open last output in nvim/bat?

        # tall layout
        enabled_layouts tall:bias=30;full_size=1;mirrored=false

      ${
        # Darwin-specific config
        if pkgs.stdenv.isDarwin
        then ''
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

          touch_scroll_multiplier 1

          macos_quit_when_last_window_closed yes

          map cmd+shift+d launch --type=overlay --hold kitty-debug-window

          map --when-focus-on "title:.*✳.*" enter send_text all \x0a
          map --when-focus-on "title:.*✳.*" cmd+enter send_key enter
        ''
        # linux specific (some of this is system/hardware specific.)
        else ''
          touch_scroll_multiplier 6.5

          map super+shift+d launch --type=overlay --hold kitty-debug-window

          map --when-focus-on "title:.*✳.*" enter send_text all \x0a
          map --when-focus-on "title:.*✳.*" super+enter send_key enter
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
      color0 = "#${theme.dark.base00}"; # black
      color1 = "#${sa theme.dark.base08}"; # red
      color2 = "#${sa theme.dark.base0B}"; # green
      color3 = "#${sa theme.dark.base0A}"; # Yellow
      color4 = "#${sa theme.dark.base0D}"; # Blue
      color5 = "#${sa theme.dark.base0E}"; # Magenta
      color6 = "#${sa theme.dark.base0C}"; # Cyan
      color7 = "#${theme.dark.base06}"; # White

      # Bright colors adjusted for more lightness and saturation
      color8 = "#${theme.dark.base03}"; # Bright Black (Gray)
      color9 = "#${theme.dark.base08}"; # Bright Red
      color10 = "#${theme.dark.base0B}"; # Bright Green
      color11 = "#${theme.dark.base0A}"; # Bright Yellow
      color12 = "#${theme.dark.base0D}"; # Bright Blue
      color13 = "#${theme.dark.base0E}"; # Bright Magenta
      color14 = "#${theme.dark.base0C}"; # Bright Cyan
      color15 = "#${theme.dark.base07}"; # Bright White

      # Derived colors
      foreground = "#${theme.dark.base06}";
      background = "#${theme.dark.base00}"; # Use base00 directly
      selection_background = "#${theme.dark.base02}"; # Use base02 (Dark Selection Background)
      selection_foreground = "none";
      url_color = "#${theme.dark.base0C}";
      cursor = "#${theme.dark.base05}";

      active_border_color = "#${theme.dark.base0D}";
      inactive_border_color = "#${theme.dark.base03}";
      active_tab_background = "#${theme.dark.base01}"; # Use base01 (Dark Background highlight)
      active_tab_foreground = "#${theme.dark.base07}";
      inactive_tab_background = "#${theme.dark.base00}";
      inactive_tab_foreground = "#${theme.dark.base05}";
      tab_bar_background = "#${theme.dark.base00}";

      visual_bell_color = "#${theme.dark.base08}";

      mark1_foreground = "#${theme.dark.base00}";
      mark1_background = "#${theme.dark.base0C}";
      mark2_foreground = "#${theme.dark.base00}";
      mark2_background = "#${theme.dark.base0D}";
      mark3_foreground = "#${theme.dark.base00}";
      mark3_background = "#${theme.dark.base0E}";

      window_padding_width = 0;
    };
  };
}

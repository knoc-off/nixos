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
  # ============================================================================
  # KITTY FEATURES NOT AVAILABLE IN GHOSTTY
  # ============================================================================
  #
  # 1. Remote Control Socket
  #    Kitty had: allow_remote_control socket, listen_on unix:/tmp/kitty-{kitty_pid}.socket
  #    Used for: window focus navigation, debug overlays, runtime theme switching
  #    Alternative: Use Hyprland keybindings for window management
  #
  # 2. Custom Python Tab Bar
  #    Kitty had: tab_bar.py with battery indicator, clock, date
  #    Alternative: Use ghostty's built-in tab bar (simpler, no custom scripting)
  #
  # 3. Window Layouts
  #    Kitty had: enabled_layouts tall:bias=30;full_size=1;mirrored=false
  #    Alternative: Use Hyprland tiling for layout management
  #
  # 4. Conditional Keybindings
  #    Kitty had: map --when-focus-on "title:.*✳.*" enter send_text all \x0a
  #    Purpose: Special enter key behavior for specific window titles
  #    Alternative: Not available in ghostty
  #
  # 5. Platform-specific Navigation
  #    Kitty had: alt+hjkl/arrows for neighboring_window movement (macOS)
  #    Used for: Moving focus between split windows
  #    Alternative: Use Hyprland window focus bindings
  #
  # 6. SSH Kitten Integration
  #    Kitty had: kitty +kitten ssh (auto-copies terminfo to remote)
  #    Alternative: Standard SSH, manual terminfo setup if needed
  #
  # 7. Runtime Theme Switching
  #    Kitty had: kittydark/kittylight scripts using `kitty @ set-colors`
  #    Alternative: Static theme configuration
  #
  # 8. Debug Window Script
  #    Kitty had: kitty-debug-window script using `kitten @ ls` to inspect windows
  #    Used for: Debugging window state and configuration
  #    Alternative: Not available in ghostty
  #
  # 9. Mouse Actions
  #    Kitty had: mouse_map right press ungrabbed mouse_select_command_output
  #    Purpose: Right-click to select command output
  #    Alternative: May not be available in ghostty
  #
  # 10. Dropdown Terminal Integration
  #     Kitty had: Special dropdown terminal with class "kitty-dropterm" via Hyprland
  #     Bound to: SUPER+T
  #     Alternative: Can recreate with Hyprland rules if needed
  # ============================================================================

  home.sessionVariables = {
    TERMINAL = "ghostty";
  };

  programs.ghostty = {
    enable = true;

    enableZshIntegration = true;

    settings = {
      # Font configuration (from kitty)
      font-family = "FiraCode Nerd Font Mono";
      font-size = 15;

      # Window appearance
      window-padding-x = 0;
      window-padding-y = 0;

      # Audio/Visual bells
      # Kitty had: enable_audio_bell = no, visual_bell_duration = 0.0
      # Ghostty equivalent:
      command = ""; # Disable bell command

      # Focus behavior
      focus-follows-mouse = true;

      # Base16 color scheme (ported from kitty)
      # Terminal colors (0-15)
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

      # Core colors
      background = "${theme.dark.base00}";
      foreground = "${theme.dark.base06}";

      # Cursor
      cursor-color = "${theme.dark.base05}";

      # Selection
      selection-background = "${theme.dark.base02}";
      selection-foreground = "${theme.dark.base06}";

      # Keybindings using super as main modifier
      # Note: Kanata maps caps→super when ghostty is focused (via hyprkan)
      keybind = let
        isLinux = pkgs.stdenv.isLinux;
        isDarwin = pkgs.stdenv.isDarwin;
      in
        [
          "clear" # Clear default keybinds first

          # Core actions
          "super+c=copy_to_clipboard"
          "super+v=paste_from_clipboard"
          "super+a=select_all"
          "super+q=quit"
        ]
        # Windows & Tabs (platform-specific)
        ++ lib.optionals isLinux [
          "super+t=new_window" # New window (inherits CWD)
          "super+shift+t=new_tab" # New tab
        ]
        ++ lib.optionals isDarwin [
          "super+t=new_tab" # New tab
          "super+shift+t=new_window" # New window
        ]
        ++ [
          "super+w=close_surface" # Close tab

          # Tab navigation (1-9)
          "super+one=goto_tab:1"
          "super+two=goto_tab:2"
          "super+three=goto_tab:3"
          "super+four=goto_tab:4"
          "super+five=goto_tab:5"
          "super+six=goto_tab:6"
          "super+seven=goto_tab:7"
          "super+eight=goto_tab:8"
          "super+nine=goto_tab:9"

          # Font size
          "super+equal=increase_font_size:1"
          "super+minus=decrease_font_size:1"
          "super+zero=reset_font_size"

          "super+shift+enter=new_split:right" # New split to the right (stack layout)
          #"super+shift+enter=new_split:down" # Force split downward (for stacking)
          "super+shift+w=close_surface" # Close split

          # Split navigation (vim-style, focus-follows-mouse enabled)
          "super+h=goto_split:left"
          "super+j=goto_split:bottom"
          "super+k=goto_split:top"
          "super+l=goto_split:right"

          # Split resizing (for 60/40 master-stack ratio)
          "super+ctrl+h=resize_split:left,10"
          "super+ctrl+j=resize_split:down,10"
          "super+ctrl+k=resize_split:up,10"
          "super+ctrl+l=resize_split:right,10"
        ];
    };
  };
}

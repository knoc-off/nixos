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
      # Note: Kitty had focus_follows_mouse = yes
      # Check if ghostty supports this - may need to verify

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

      # Basic keybindings (ported from kitty)
      keybind = [
        # Clear keybinds
        "clear"

        # Copy/Paste/Select (kitty: super+c/v/a)
        "super+c=copy_to_clipboard"
        "super+v=paste_from_clipboard"
        # Note: select_all may not exist in ghostty, need to verify

        # Tab management (kitty: super+t/w)
        "super+t=new_tab"
        "super+w=close_surface"

        # Split window (kitty: alt+enter for split)
        # Note: ghostty may use different split commands
        # "alt+enter=???" # TODO: Find ghostty equivalent for split

        # Clear terminal (kitty: ctrl+l)
        # Note: This was for clearing to cursor
        # May not have exact equivalent

        # Search scrollback (kitty: super+f for show_scrollback)
        # Note: ghostty may have different scrollback search

        # Platform-specific keybindings would go here
        # Kitty had different bindings for macOS vs Linux
      ];
    };
  };
}

{ config, pkgs }:
{

  home = {
    sessionVariables = {
      # Editor and shell
      EDITOR = "nvim";
      TERMINAL = "kitty";

      # Browser
      BROWSER = "firefox";

      GTK_THEME = "Adwaita:dark";
      GTK2_RC_FILES = "${pkgs.theme-obsidian2}/share/themes/Obsidian-2/gtk-2.0/gtkrc";
      QT_STYLE_OVERRIDE = "adwaita-dark";

      # GUI toolkit settings
      QT_SCALE_FACTOR = "1";
      QT_QPA_PLATFORM = "wayland";
      QT_WAYLAND_DISABLE_WINDOWDECORATION = "1";
      QT_AUTO_SCREEN_SCALE_FACTOR = "1";
      CLUTTER_BACKEND = "wayland";

      # Video and graphics
      MOZ_ENABLE_WAYLAND = "1";
      SDL_VIDEODRIVER = "wayland";
      WLR_RENDERER = "vulkan";
      # WLR_NO_HARDWARE_CURSORS = "1"; # if no cursor,uncomment this line

      # Java GUI settings
      _JAVA_AWT_WM_NONREPARENTING = "1";

      # Desktop environment settings
      XDG_CURRENT_DESKTOP = "Hyprland";
      XDG_SESSION_DESKTOP = "Hyprland";
      XDG_SESSION_TYPE = "wayland";

      # File path settings
      XDG_CACHE_HOME = "\${HOME}/.cache";
      XDG_CONFIG_HOME = "\${HOME}/.config";
      XDG_BIN_HOME = "\${HOME}/.local/bin";
      XDG_DATA_HOME = "\${HOME}/.local/share";

    };
  };
}

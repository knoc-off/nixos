{
  config,
  lib,
  pkgs,
  ...
}: {
  home = {
    file = {
      mnt = {
        recursive = true;
        source =
          config.lib.file.mkOutOfStoreSymlink
          "/run/media/${config.home.username}";
      };

      nixos = {
        recursive = true;
        source = config.lib.file.mkOutOfStoreSymlink "/etc/nixos/";
      };
    };

    sessionVariables = {
      ANTHROPIC_API_KEY = "$(cat /run/secrets/ANTHROPIC_API_KEY)";
      OPENROUTER_API_KEY = "$(cat /etc/secrets/gpt/openrouter )";

      QT_SCALE_FACTOR = "1";
      QT_QPA_PLATFORM = "wayland";
      QT_WAYLAND_DISABLE_WINDOWDECORATION = "1";
      QT_AUTO_SCREEN_SCALE_FACTOR = "1";
      CLUTTER_BACKEND = "wayland";

      XDG_CURRENT_DESKTOP = "Hyprland";
      XDG_SESSION_DESKTOP = "Hyprland";
      XDG_SESSION_TYPE = "wayland";

      XDG_CACHE_HOME = "\${HOME}/.cache";
      XDG_CONFIG_HOME = "\${HOME}/.config";
      XDG_BIN_HOME = "\${HOME}/.local/bin";
      XDG_DATA_HOME = "\${HOME}/.local/share";
    };
  };
}


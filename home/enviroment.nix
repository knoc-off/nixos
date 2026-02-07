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

      XDG_CURRENT_DESKTOP = "niri";
      XDG_SESSION_DESKTOP = "niri";
      XDG_SESSION_TYPE = "wayland";

      XDG_CACHE_HOME = "\${HOME}/.cache";
      XDG_CONFIG_HOME = "\${HOME}/.config";
      XDG_BIN_HOME = "\${HOME}/.local/bin";
      XDG_DATA_HOME = "\${HOME}/.local/share";
    };
  };
}


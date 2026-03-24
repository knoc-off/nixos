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
      SOPS_AGE_KEY_CMD = "sudo ${pkgs.ssh-to-age}/bin/ssh-to-age -private-key -i /etc/ssh/ssh_host_ed25519_key";

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

{
  config,
  lib,
  pkgs,
  ...
}: {
  # programs.bash.enable = true;
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

    # this should be distributed in each file that adds the package.
    sessionVariables = {
      ANTHROPIC_API_KEY = "$(cat /run/secrets/ANTHROPIC_API_KEY)";
      OPENROUTER_API_KEY = "$(cat /etc/secrets/gpt/openrouter )"; # SOPS !TODO

      # GUI toolkit settings
      QT_SCALE_FACTOR = "1";
      QT_QPA_PLATFORM = "wayland"; # needs   libsForQt5.qt5.qtwayland
      QT_WAYLAND_DISABLE_WINDOWDECORATION = "1";
      QT_AUTO_SCREEN_SCALE_FACTOR = "1";
      CLUTTER_BACKEND = "wayland";

      # Desktop environment settings
      XDG_CURRENT_DESKTOP = "Hyprland";
      XDG_SESSION_DESKTOP = "Hyprland";
      XDG_SESSION_TYPE = "wayland";

      # File path settings
      XDG_CACHE_HOME = "\${HOME}/.cache";
      XDG_CONFIG_HOME = "\${HOME}/.config";
      XDG_BIN_HOME = "\${HOME}/.local/bin";
      XDG_DATA_HOME = "\${HOME}/.local/share";
      #XDG_DATA_DIRS = "$XDG_DATA_DIRS:/usr/share:/usr/local/share";
    };
  };

  # enable qt themes
  #qt = {
  #  enable = true;
  #  platformTheme.name = "gtk3";

  #  style = {
  #    name = "gtk3";
  #    #package = pkgs.adwaita-qt;
  #  };
  #};

  ## enable gtk themes
  #gtk = let
  #  extra3-4Config = {
  #    gtk-application-prefer-dark-theme = 1;
  #  };
  #in {
  #  enable = true;
  #  theme = {
  #    name = "Fluent-Dark";
  #    package = pkgs.fluent-gtk-theme;
  #  };
  #  iconTheme = {
  #    name = "Fluent-Dark";
  #    package = pkgs.fluent-icon-theme;
  #  };
  #  cursorTheme = {
  #    name = "Vanilla-DMZ";
  #    package = pkgs.vanilla-dmz;
  #  };

  #  gtk3.extraConfig = extra3-4Config;
  #  gtk4.extraConfig = extra3-4Config;
  #};

  #dconf = {
  #  enable = true;
  #  settings = {
  #    "org/gnome/desktop/interface" = {
  #      color-scheme = "prefer-dark";
  #      gtk-theme = "Fluent-Dark";
  #      icon-theme = "Fluent-Dark";
  #      cursor-theme = "Vanilla-DMZ";
  #      #gtk-theme = "Adwaita-dark";
  #      #icon-theme = "Adwaita-dark";
  #      #cursor-theme = "Adwaita-dark";
  #    };
  #    "org/gnome/shell/extensions/user-theme" = {
  #      name = "Fluent-Dark";
  #    };
  #    "org/gnome/gedit/preferences/editor" = {
  #      scheme = "oblivion";
  #    };
  #    "org/gnome/Terminal/Legacy/Settings" = {
  #      theme-variant = "dark";
  #    };
  #  };
  #};
}
#env = GDK_BACKEND,wayland,x11
#env = QT_QPA_PLATFORM,wayland;xcb
#env = SDL_VIDEODRIVER,wayland
#env = CLUTTER_BACKEND,wayland
#env = XDG_CURRENT_DESKTOP,Hyprland
#env = XDG_SESSION_TYPE,wayland
#env = XDG_SESSION_DESKTOP,Hyprland
#env = QT_AUTO_SCREEN_SCALE_FACTOR,1
##env = GTK_THEME,Breeze-Dark
##env = QT_STYLE_OVERRIDE,Breeze-Dark
#env = XCURSOR_THEME,Future-Cursors
#env = XCURSOR_SIZE,24
#env = QT_WAYLAND_DISABLE_WINDOWDECORATION,1


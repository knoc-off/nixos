{ config, pkgs, ... }:

let
  # Define common themes and icon sets
  commonTheme = {
    gtkTheme = {
      name = "Adwaita-dark";
      package = pkgs.gnome.gnome-themes-extra;
    };
    qtStyle = {
      name = "breeze-dark";
      package = pkgs.breeze;
    };
    iconTheme = {
      name = "Breeze";
      package = pkgs.breeze-icon-theme;
    };
    cursorTheme = {
      name = "Breeze";
      package = pkgs.breeze-cursor-theme;
      size = 24;
    };
  };
in
{
  # GTK Configuration
  gtk = {
    enable = true;

    theme = {
      name = commonTheme.gtkTheme.name;
      package = commonTheme.gtkTheme.package;
    };

    iconTheme = {
      name = commonTheme.iconTheme.name;
      package = commonTheme.iconTheme.package;
    };

    cursorTheme = {
      name = commonTheme.cursorTheme.name;
      package = commonTheme.cursorTheme.package;
      size = commonTheme.cursorTheme.size;
    };

    # GTK2 Settings
    gtk2 = {
      extraConfig = "gtk-can-change-accels = 1";
      configLocation = "${config.home.homeDirectory}/.gtkrc-2.0";
    };

    # GTK3 Settings
    gtk3 = {
      bookmarks = [ "file://${config.home.homeDirectory}/Documents" ];
      extraConfig = {
        "gtk-theme-name" = commonTheme.gtkTheme.name;
        "gtk-icon-theme-name" = commonTheme.iconTheme.name;
      };
      extraCss = ''
        @define-color bg_color #2e3436;
        window {
          background-color: @bg_color;
        }
      '';
    };

    # GTK4 Settings
    gtk4 = {
      extraConfig = {
        "gtk-theme-name" = commonTheme.gtkTheme.name;
        "gtk-icon-theme-name" = commonTheme.iconTheme.name;
      };
      extraCss = ''
        @define-color bg_color #2e3436;
        window {
          background-color: @bg_color;
        }
      '';
    };
  };

  # Qt Configuration
  qt = {
    enable = true;

    style = {
      name = commonTheme.qtStyle.name;
      package = commonTheme.qtStyle.package;
    };

    iconTheme = {
      name = commonTheme.iconTheme.name;
      package = commonTheme.iconTheme.package;
    };

    cursorTheme = {
      name = commonTheme.cursorTheme.name;
      package = commonTheme.cursorTheme.package;
      size = commonTheme.cursorTheme.size;
    };

    platformTheme = "kde"; # Integrates with KDE Plasma settings

    # Set Qt environment variables for theming
    sessionVariables = {
      QT_QPA_PLATFORMTHEME = "kde";
      QT_STYLE_OVERRIDE = commonTheme.qtStyle.name;
    };

    # Ensure Kvantum is available for advanced theming (optional)
    stylePackages = [
      commonTheme.qtStyle.package
      pkgs.kvantum
    ];
  };

  # Ensure required packages are installed
  home.packages = with pkgs; [
    commonTheme.gtkTheme.package
    commonTheme.qtStyle.package
    commonTheme.iconTheme.package
    commonTheme.cursorTheme.package
    # Add Kvantum if using for advanced Qt theming
    kvantum
  ];

  # Set XDG data directories if necessary
  xdg = {
    configFile."gtk-3.0/settings.ini".text = ''
      [Settings]
      gtk-theme-name = ${commonTheme.gtkTheme.name}
      gtk-icon-theme-name = ${commonTheme.iconTheme.name}
      gtk-cursor-theme-name = ${commonTheme.cursorTheme.name}
      gtk-cursor-theme-size = ${toString commonTheme.cursorTheme.size}
      gtk-application-prefer-dark-theme=1
    '';
  };
}

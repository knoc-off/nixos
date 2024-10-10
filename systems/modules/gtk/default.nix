{ config, lib, pkgs, ... }: {

  imports = [ ./settings.nix ];

  gtkThemeSymlinks = {
    enable = lib.mkDefault true;
    gtk2 = lib.mkDefault {
      themeName = "Fluent-Dark";
      themePackage = pkgs.fluent-gtk-theme;
    };
    gtk3 = lib.mkDefault {
      themeName = "Fluent-Dark";
      themePackage = pkgs.fluent-gtk-theme;
    };
    gtk4 = lib.mkDefault {
      themeName = "Fluent-Dark";
      themePackage = pkgs.fluent-gtk-theme;
    };
    symlinks = lib.mkDefault {
      "gtk-2.0/gtkrc" = pkgs.writeText "gtkrc"
        "gtk-application-prefer-dark-theme=1";
      "gtk-3.0/settings.ini" = pkgs.writeText "gtk3-settings.ini" ''
        [Settings]
        gtk-application-prefer-dark-theme=1
        gtk-error-bell=false
      '';
      "gtk-4.0/settings.ini" = pkgs.writeText "gtk4-settings.ini" ''
        [Settings]
        gtk-application-prefer-dark-theme=1
        gtk-error-bell=false
      '';
    };
  };

}

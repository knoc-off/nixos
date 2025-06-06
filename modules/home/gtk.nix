{ self, pkgs, config, ... }:
{
  gtk = {
    enable = true;

    theme = {
    	name = "materia-theme";
      package = self.packages.${pkgs.system}.materia-theme;
    };
    iconTheme = {
      name = "Nordzy";
      package = pkgs.nordzy-icon-theme;
    };
    gtk3.extraConfig = {
      gtk-application-prefer-dark-theme=1;
    };
    gtk4.extraConfig = {
      gtk-application-prefer-dark-theme=1;
    };
  };

  qt = {
    enable = true;
    platformTheme.name = "gtk";
    # style = {
    #   name = "materia-theme";
    #   package = pkgs.adwaita-qt;
    # };
  };

  dconf.settings = {
    "org/gnome/desktop/interface" = {
      color-scheme = "prefer-dark";
      cursor-size = 24;
    };
    "org/gnome/shell/extensions/user-theme" = {
      name = "adwaita-dark";
    };
  };

  home.pointerCursor = {
    package = pkgs.posy-cursors;
    name = "Posy_Cursor_Black";
    size = 24;
    gtk.enable = true;
    x11.enable = true;
  };

  home.sessionVariables.GTK_THEME = "materia-theme";
}

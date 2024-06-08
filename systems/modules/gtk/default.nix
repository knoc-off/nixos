{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.gtkThemeSymlinks;
in
{
  options.services.gtkThemeSymlinks = {
    enable = mkOption {
      type = types.bool;
      default = false;
      description = "Enable GTK theme symlinks.";
    };

    gtk2 = {
      themeName = mkOption {
        type = types.str;
        default = "Fluent-Dark";
        description = "The name of the GTK 2.0 theme to symlink.";
      };

      themePackage = mkOption {
        type = types.package;
        default = pkgs.fluent-gtk-theme;
        description = "The package containing the GTK 2.0 theme.";
      };
    };

    gtk3 = {
      themeName = mkOption {
        type = types.str;
        default = "Fluent-Dark";
        description = "The name of the GTK 3.0 theme to symlink.";
      };

      themePackage = mkOption {
        type = types.package;
        default = pkgs.fluent-gtk-theme;
        description = "The package containing the GTK 3.0 theme.";
      };
    };

    gtk4 = {
      themeName = mkOption {
        type = types.str;
        default = "Fluent-Dark";
        description = "The name of the GTK 4.0 theme to symlink.";
      };

      themePackage = mkOption {
        type = types.package;
        default = pkgs.fluent-gtk-theme;
        description = "The package containing the GTK 4.0 theme.";
      };
    };

    symlinks = mkOption {
      type = types.attrsOf (types.either types.path types.lines);
      default = {};
      example = literalExpression ''
        {
          "gtk-2.0/gtkrc" = pkgs.writeText "gtkrc" "gtk-application-prefer-dark-theme=1";
          "gtk-3.0/settings.ini" = pkgs.writeText "gtk3-settings.ini" '''
            [Settings]
            gtk-application-prefer-dark-theme=1
            gtk-error-bell=false
          ''';
        }
      '';
      description = "A set of files to symlink in the theme.";
    };
  };

  config = mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      (pkgs.stdenv.mkDerivation {
        name = "gtk-theme-symlinks";
        src = cfg.gtk2.themePackage.src;

        buildInputs = [ pkgs.glib ];

        installPhase = ''
          mkdir -p $out/share/themes/${cfg.gtk2.themeName}/gtk-2.0
          mkdir -p $out/share/themes/${cfg.gtk3.themeName}/gtk-3.0
          mkdir -p $out/share/themes/${cfg.gtk4.themeName}/gtk-4.0

          cp -rL ${cfg.gtk2.themePackage}/share/themes/${cfg.gtk2.themeName}/gtk-2.0/* $out/share/themes/${cfg.gtk2.themeName}/gtk-2.0/
          cp -rL ${cfg.gtk3.themePackage}/share/themes/${cfg.gtk3.themeName}/gtk-3.0/* $out/share/themes/${cfg.gtk3.themeName}/gtk-3.0/
          cp -rL ${cfg.gtk4.themePackage}/share/themes/${cfg.gtk4.themeName}/gtk-4.0/* $out/share/themes/${cfg.gtk4.themeName}/gtk-4.0/

          # Create symlinks
          ${concatStringsSep "\n" (mapAttrsToList (file: target: ''
            ln -sf ${target} $out/share/themes/${cfg.gtk2.themeName}/${file}
          '') cfg.symlinks)}
        '';

        meta = with lib; {
          description = "GTK theme with symlinked files";
          license = licenses.mit; # Change to the actual license of the theme
          maintainers = [ maintainers.yourself ];
          platforms = platforms.linux;
        };
      })
    ];

    environment.etc = {
      "xdg/gtk-2.0".source = "/run/current-system/sw/share/themes/${cfg.gtk2.themeName}/gtk-2.0";
      "xdg/gtk-3.0".source = "/run/current-system/sw/share/themes/${cfg.gtk3.themeName}/gtk-3.0";
      "xdg/gtk-4.0".source = "/run/current-system/sw/share/themes/${cfg.gtk4.themeName}/gtk-4.0";
    };
  };
}

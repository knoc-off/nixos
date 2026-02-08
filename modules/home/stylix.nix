{ inputs, theme, pkgs, lib, ... }:
{
  imports = [ inputs.stylix.homeModules.stylix ];

  stylix = {
    enable = true;

    # CRITICAL: Disable auto-theming to prevent Stylix from "leaking" into other configs
    # Only explicitly enabled targets will be themed
    autoEnable = false;

    # Use your base16 colors from theme.nix (dark variant)
    base16Scheme = {
      inherit (theme.dark)
        base00 base01 base02 base03 base04 base05 base06 base07
        base08 base09 base0A base0B base0C base0D base0E base0F;
    };

    polarity = "dark";

    # Stylix requires an image, but we can use a generated one from the base color
    image = pkgs.runCommand "wallpaper.png" { buildInputs = [ pkgs.imagemagick ]; } ''
      magick -size 1x1 xc:'#${theme.dark.base00}' $out
    '';

    # Enable ONLY the targets you want
    targets = {
      gtk.enable = true;
      qt.enable = true;
    };

    # Cursor configuration (keeping your existing preference)
    cursor = {
      package = pkgs.posy-cursors;
      name = "Posy_Cursor_Black";
      size = 24;
    };

    # Font configuration with sensible defaults
    fonts = {
      serif = {
        package = pkgs.dejavu_fonts;
        name = "DejaVu Serif";
      };
      sansSerif = {
        package = pkgs.dejavu_fonts;
        name = "DejaVu Sans";
      };
      monospace = {
        package = pkgs.dejavu_fonts;
        name = "DejaVu Sans Mono";
      };
      emoji = {
        package = pkgs.noto-fonts-emoji;
        name = "Noto Color Emoji";
      };
      sizes = {
        applications = 11;
        desktop = 11;
        popups = 11;
        terminal = 11;
      };
    };
  };

  # Enable dconf for GTK settings to work properly
  dconf.enable = true;

  # Icon theme configuration (fixes missing icons in Noctalia, Kitty, etc.)
  gtk.iconTheme = {
    package = pkgs.papirus-icon-theme;
    name = "Papirus-Dark";
  };
}

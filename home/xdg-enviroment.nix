{ pkgs, self, ... }:

let
  mimeSets = {
    application = {
      # Existing entries
      pdf = [ "org.gnome.Evince.desktop" ];
      json = [ "kitty-neovim.desktop" ];
      xml = [ "kitty-neovim.desktop" ];
      "x-shellscript" = [ "kitty-neovim.desktop" ];
      "x-perl" = [ "kitty-neovim.desktop" ];
      "x-python" = [ "kitty-neovim.desktop" ];
      "x-ruby" = [ "kitty-neovim.desktop" ];
      "x-php" = [ "kitty-neovim.desktop" ];
      "x-java" = [ "kitty-neovim.desktop" ];
      "x-javascript" = [ "kitty-neovim.desktop" ];
      zip = [ "org.gnome.FileRoller.desktop" ];
      "x-rar" = [ "org.gnome.FileRoller.desktop" ];
      "x-7z-compressed" = [ "org.gnome.FileRoller.desktop" ];
      "x-tar" = [ "org.gnome.FileRoller.desktop" ];
      "x-gzip" = [ "org.gnome.FileRoller.desktop" ];
      "x-bzip2" = [ "org.gnome.FileRoller.desktop" ];


      # Example: Use kitty-neovim for markdown
      # "markdown" = [ "kitty-neovim.desktop" ];

      # Example: Use kitty-neovim for LaTeX
      # "x-tex" = [ "kitty-neovim.desktop" ];

      # Example: Use kitty-neovim for Rust
      # "x-rust" = [ "kitty-neovim.desktop" ];

      # Example: Use LibreOffice for .doc or .docx
      # "msword"        = [ "libreoffice-writer.desktop" ];
      # "vnd.openxmlformats-officedocument.wordprocessingml.document" = [ "libreoffice-writer.desktop" ];

      # Example: Conditionally enable Go file type
      # "x-golang" = lib.mkIf (lib.elem pkgs.go config.environment.systemPackages) {
      #   [ "kitty-neovim.desktop" ];
      # };
    };

    video = {
      mp4 = [ "mpv.desktop" ];
      "x-matroska" = [ "mpv.desktop" ];
      webm = [ "mpv.desktop" ];

      # "x-msvideo" = [ "mpv.desktop" ];
      # "ogg"       = [ "mpv.desktop" ];
    };

    audio = {
      mpeg = [ "mpv.desktop" ];
      ogg = [ "mpv.desktop" ];
      wav = [ "mpv.desktop" ];
      flac = [ "mpv.desktop" ];

      # "x-ms-wma" = [ "mpv.desktop" ];
      # "aac"      = [ "mpv.desktop" ];
    };

    image = {
      bmp = [ "feh.desktop" ];
      gif = [ "feh.desktop" ];
      jpeg = [ "feh.desktop" ];
      png = [ "feh.desktop" ];
      "svg+xml" = [ "feh.desktop" ];
      tiff = [ "feh.desktop" ];

      # "x-icns" = [ "feh.desktop" ];
      # "x-portable-pixmap" = [ "feh.desktop" ];
    };

    inode = {
      directory = [ "org.gnome.Nautilus.desktop" ];
      # lib.mkIf (lib.elem pkgs.<pkg> config.environment.systemPackages)

      # # Possible custom handling for certain directories
      # # "mount-point" = [ "org.gnome.DiskUtility.desktop" ];
    };
  };

  toMimeApps = attrs:
    builtins.foldl' (acc: topLevelName:
      let
        subSet = attrs.${topLevelName};
        # Map each key in subSet (e.g. "pdf", "mp4") to full MIME string
        mapped = builtins.mapAttrs (subKey: desktopFiles:
          # subKey = "pdf" -> "application/pdf"
          # topLevelName = "application", "image", "video", etc.
          {
            name = "${topLevelName}/${subKey}";
            value = desktopFiles;
          }) subSet;
        # fold each "name = value" pair into the main accumulator
      in builtins.foldl' (acc2: entry: acc2 // { ${entry.name} = entry.value; })
      acc (builtins.attrValues mapped)) { } (builtins.attrNames attrs);

in {
  # gnome settings app
  xdg.desktopEntries."org.gnome.Settings" = {
    name = "Settings";
    comment = "Gnome Control Center";
    icon = "org.gnome.Settings";
    exec =
      "env XDG_CURRENT_DESKTOP=gnome ${pkgs.gnome-control-center}/bin/gnome-control-center";
    categories = [ "X-Preferences" ];
    terminal = false;
  };

  xdg.desktopEntries = {
    kitty-neovim = {
      name = "Kitty Neovim";
      genericName = "Text Editor";
      exec = "kitty --detach nvim %U";
      icon = "${pkgs.neovim}/share/icons/hicolor/128x128/apps/nvim.png";
      terminal = false;
      categories = [ "Application" "Development" "IDE" ];
      mimeType = [ "text/plain" ];
    };
  };

  home.packages = with pkgs; [
    # move to desktop module?
    gnome-disk-utility

    #gedit
    f3d

    #(gimp-with-plugins.override { plugins = with gimpPlugins; [ resynthesizer ]; })
    gimp

    feh
  ];

  # XDG settings
  xdg.mimeApps = {
    enable = true;

    defaultApplications = toMimeApps mimeSets;
    #defaultApplications =
    #mkMimeMap { prefix = "application"; entries = mimeDefaults.application; }
    #// mkMimeMap { prefix = "text";        entries = mimeDefaults.text; }
    #// mkMimeMap { prefix = "video";       entries = mimeDefaults.video; }
    #// mkMimeMap { prefix = "audio";       entries = mimeDefaults.audio; }
    #// mkMimeMap { prefix = "image";       entries = mimeDefaults.image; };
  };
}

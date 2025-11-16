{pkgs, ...}: let
  toMimeApps = attrs:
    builtins.foldl' (acc: topLevelName: let
      subSet = attrs.${topLevelName};
      # Map each key in subSet (e.g. "pdf", "mp4") to full MIME string
      mapped = builtins.mapAttrs (subKey: desktopFiles:
        # subKey = "pdf" -> "application/pdf"
        # topLevelName = "application", "image", "video", etc.
        {
          name = "${topLevelName}/${subKey}";
          value = desktopFiles;
        })
      subSet;
      # fold each "name = value" pair into the main accumulator
    in
      builtins.foldl' (acc2: entry: acc2 // {${entry.name} = entry.value;})
      acc (builtins.attrValues mapped)) {} (builtins.attrNames attrs);
in {
  # gnome settings app
  xdg.desktopEntries."org.gnome.Settings" = {
    name = "Settings";
    comment = "Gnome Control Center";
    icon = "org.gnome.Settings";
    exec = "env XDG_CURRENT_DESKTOP=gnome ${pkgs.gnome-control-center}/bin/gnome-control-center";
    categories = ["X-Preferences"];
    terminal = false;
  };

  home.packages = with pkgs; [
    # move to desktop module?
    gnome-disk-utility

    #gedit
    f3d

    #(gimp-with-plugins.override { plugins = with gimpPlugins; [ resynthesizer ]; })
    #gimp

    feh
  ];

  # XDG settings
  xdg.mimeApps = {
    enable = true;

    defaultApplications =
      toMimeApps
      {
        application = {
          # Existing entries
          pdf = ["org.gnome.Evince.desktop"];
          json = ["term-neovim.desktop"];
          xml = ["term-neovim.desktop"];
          "x-shellscript" = ["term-neovim.desktop"];
          "x-perl" = ["term-neovim.desktop"];
          "x-python" = ["term-neovim.desktop"];
          "x-ruby" = ["term-neovim.desktop"];
          "x-php" = ["term-neovim.desktop"];
          "x-java" = ["term-neovim.desktop"];
          "x-javascript" = ["term-neovim.desktop"];
          zip = ["org.gnome.FileRoller.desktop"];
          "x-rar" = ["org.gnome.FileRoller.desktop"];
          "x-7z-compressed" = ["org.gnome.FileRoller.desktop"];
          "x-tar" = ["org.gnome.FileRoller.desktop"];
          "x-gzip" = ["org.gnome.FileRoller.desktop"];
          "x-bzip2" = ["org.gnome.FileRoller.desktop"];

          # Example: Use term-neovim for markdown
          # "markdown" = [ "term-neovim.desktop" ];

          # Example: Use term-neovim for LaTeX
          # "x-tex" = [ "term-neovim.desktop" ];

          # Example: Use term-neovim for Rust
          # "x-rust" = [ "term-neovim.desktop" ];

          # Example: Use LibreOffice for .doc or .docx
          # "msword"        = [ "libreoffice-writer.desktop" ];
          # "vnd.openxmlformats-officedocument.wordprocessingml.document" = [ "libreoffice-writer.desktop" ];

          # Example: Conditionally enable Go file type
          # "x-golang" = lib.mkIf (lib.elem pkgs.go config.environment.systemPackages) {
          #   [ "term-neovim.desktop" ];
          # };
        };

        video = {
          mp4 = ["mpv.desktop"];
          "x-matroska" = ["mpv.desktop"];
          webm = ["mpv.desktop"];

          # "x-msvideo" = [ "mpv.desktop" ];
          # "ogg"       = [ "mpv.desktop" ];
        };

        audio = {
          mpeg = ["mpv.desktop"];
          ogg = ["mpv.desktop"];
          wav = ["mpv.desktop"];
          flac = ["mpv.desktop"];

          # "x-ms-wma" = [ "mpv.desktop" ];
          # "aac"      = [ "mpv.desktop" ];
        };

        image = {
          bmp = ["qview.desktop"];
          gif = ["qview.desktop"];
          jpeg = ["qview.desktop"];
          png = ["qview.desktop"];
          "svg+xml" = ["qview.desktop"];
          tiff = ["qview.desktop"];

          # "x-icns" = [ "qview.desktop" ];
          # "x-portable-pixmap" = [ "qview.desktop" ];
        };

        inode = {
          directory = ["org.gnome.Nautilus.desktop"];
          # lib.mkIf (lib.elem pkgs.<pkg> config.environment.systemPackages)

          # # Possible custom handling for certain directories
          # # "mount-point" = [ "org.gnome.DiskUtility.desktop" ];
        };
      };
    #defaultApplications =
    # mkMimeMap { prefix = "application"; entries = mimeDefaults.application; }
    # mkMimeMap { prefix = "text";        entries = mimeDefaults.text; }
    # mkMimeMap { prefix = "video";       entries = mimeDefaults.video; }
    # mkMimeMap { prefix = "audio";       entries = mimeDefaults.audio; }
    # mkMimeMap { prefix = "image";       entries = mimeDefaults.image; };
  };
}

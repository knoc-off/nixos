{ pkgs, config, lib, ... }:

let
  mimeSets = {
    application = {
      # Base applications (always active)
      pdf = [ "org.gnome.Evince.desktop" ];
      zip = [ "org.gnome.FileRoller.desktop" ];
      "vnd.rar" = [ "org.gnome.FileRoller.desktop" ];
      "x-7z-compressed" = [ "org.gnome.FileRoller.desktop" ];
      "x-tar" = [ "org.gnome.FileRoller.desktop" ];
      gzip = [ "org.gnome.FileRoller.desktop" ];
      "x-bzip2" = [ "org.gnome.FileRoller.desktop" ];
    }
    # The '//' operator merges the result of lib.mkIf with the base set
      // lib.mkIf (config.xdg.desktopEntries ? "term-neovim") {
        # These associations are added only if the 'term-neovim' desktop entry is defined
        json = [ "term-neovim.desktop" ];
        xml = [ "term-neovim.desktop" ]; # Assuming application/xml. If text/xml, move to 'text' section below.
        "x-shellscript" = [ "term-neovim.desktop" ];
        "x-perl" = [ "term-neovim.desktop" ];
        "x-python" = [ "term-neovim.desktop" ];
        "x-ruby" = [ "term-neovim.desktop" ];
        php = [ "term-neovim.desktop" ];
        javascript = [ "term-neovim.desktop" ];
      };

    text = lib.mkIf (config.xdg.desktopEntries ? "term-neovim") {
      # For .java files, assuming text/x-java-source
      "x-java-source" = [ "term-neovim.desktop" ];
      # If "application/xml" above was meant to be "text/xml", move "xml" entry here.
      # If "application/x-perl" above was meant to be "text/x-perl", move "x-perl" entry here.
      # etc. for other text types
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
      bmp = [ "qview.desktop" ];
      gif = [ "qview.desktop" ];
      jpeg = [ "qview.desktop" ];
      png = [ "qview.desktop" ];
      "svg+xml" = [ "qview.desktop" ];
      tiff = [ "qview.desktop" ];

      # "x-icns" = [ "qview.desktop" ];
      # "x-portable-pixmap" = [ "qview.desktop" ];
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

  home.packages = with pkgs; [
    # move to desktop module?
    gnome-disk-utility
    file-roller

    #gedit
    f3d

    #(gimp-with-plugins.override { plugins = with gimpPlugins; [ resynthesizer ]; })
    #gimp

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

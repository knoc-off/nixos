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
    gnome-disk-utility

    f3d

    feh
  ];

  xdg.mimeApps = {
    enable = true;

    defaultApplications =
      toMimeApps
      {
        application = {
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
        };

        video = {
          mp4 = ["mpv.desktop"];
          "x-matroska" = ["mpv.desktop"];
          webm = ["mpv.desktop"];
        };

        audio = {
          mpeg = ["mpv.desktop"];
          ogg = ["mpv.desktop"];
          wav = ["mpv.desktop"];
          flac = ["mpv.desktop"];
        };

        image = {
          bmp = ["qview.desktop"];
          gif = ["qview.desktop"];
          jpeg = ["qview.desktop"];
          png = ["qview.desktop"];
          "svg+xml" = ["qview.desktop"];
          tiff = ["qview.desktop"];
        };

        inode = {
          directory = ["org.gnome.Nautilus.desktop"];
        };
      };
  };
}

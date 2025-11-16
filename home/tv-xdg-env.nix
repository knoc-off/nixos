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
  # TV Box - Minimal media-focused XDG configuration

  home.packages = with pkgs; [
    qview # Image viewer
    # Archive support handled by Dolphin/Ark
  ];

  xdg = {
    autostart.enable = true;
    mimeApps = {
      enable = true;
      defaultApplications = toMimeApps {
        video = {
          mp4 = ["mpv.desktop"];
          x-matroska = ["mpv.desktop"];
          webm = ["mpv.desktop"];
          x-msvideo = ["mpv.desktop"];
          quicktime = ["mpv.desktop"];
          mpeg = ["mpv.desktop"];
        };

        audio = {
          mpeg = ["mpv.desktop"];
          ogg = ["mpv.desktop"];
          wav = ["mpv.desktop"];
          flac = ["mpv.desktop"];
          aac = ["mpv.desktop"];
          x-ms-wma = ["mpv.desktop"];
        };

        image = {
          jpeg = ["qview.desktop"];
          png = ["qview.desktop"];
          gif = ["qview.desktop"];
          bmp = ["qview.desktop"];
          "svg+xml" = ["qview.desktop"];
          tiff = ["qview.desktop"];
          webp = ["qview.desktop"];
        };

        inode = {
          directory = ["org.kde.dolphin.desktop"];
        };

        application = {
          zip = ["org.kde.ark.desktop"];
          x-rar = ["org.kde.ark.desktop"];
          x-7z-compressed = ["org.kde.ark.desktop"];
          x-tar = ["org.kde.ark.desktop"];
          gzip = ["org.kde.ark.desktop"];
          pdf = ["org.kde.okular.desktop"];
        };
      };
    };
  };
}

{pkgs, lib, ...}:
{
  xdg.desktopEntries = {
    firefox-minimal = {
      name = "Firefox-minimal";
      genericName = "Web Browser";
      exec = "firefox -p minimal %U";
      icon = "${pkgs.firefox}/share/icons/hicolor/128x128/apps/firefox.png";
      terminal = false;
      categories = [ "Application" "Network" "WebBrowser" ];
      mimeType = [ "text/html" "text/xml" ];
    };
  };

  home.packages = with pkgs; [

    # move to desktop module?
    gnome.gnome-disk-utility

    gedit
    # f3d


    gimp
    mpv
    feh
  ];

  # XDG settings
  xdg.mimeApps = {
    enable = true;
    associations.added = {
      "application/pdf" = ["org.gnome.Evince.desktop"];
      "text/plain" = ["org.gnome.gedit.desktop"];
      "text/html" = ["org.mozilla.firefox.desktop"];
      "application/json" = ["org.gnome.gedit.desktop"];
      "application/xml" = ["org.gnome.gedit.desktop"];
      "application/x-shellscript" = ["org.gnome.gedit.desktop"];
      "application/x-perl" = ["org.gnome.gedit.desktop"];
      "application/x-python" = ["org.gnome.gedit.desktop"];
      "application/x-ruby" = ["org.gnome.gedit.desktop"];
      "application/x-php" = ["org.gnome.gedit.desktop"];
      "application/x-java" = ["org.gnome.gedit.desktop"];
      "application/x-javascript" = ["org.gnome.gedit.desktop"];
      "video/mp4" = ["mpv.desktop"];
      "video/x-matroska" = ["mpv.desktop"];
      "video/webm" = ["mpv.desktop"];
      "audio/mpeg" = ["mpv.desktop"];
      "audio/ogg" = ["mpv.desktop"];
      "audio/wav" = ["mpv.desktop"];
      "audio/flac" = ["mpv.desktop"];
      "image/bmp" = ["feh.desktop"];
      "image/gif" = ["feh.desktop"];
      "image/jpeg" = ["feh.desktop"];
      "image/png" = ["feh.desktop"];
      "image/svg+xml" = ["feh.desktop"];
      "image/tiff" = ["feh.desktop"];
      "application/zip" = ["org.gnome.FileRoller.desktop"];
      "application/x-rar" = ["org.gnome.FileRoller.desktop"];
      "application/x-7z-compressed" = ["org.gnome.FileRoller.desktop"];
      "application/x-tar" = ["org.gnome.FileRoller.desktop"];
      "application/x-gzip" = ["org.gnome.FileRoller.desktop"];
      "application/x-bzip2" = ["org.gnome.FileRoller.desktop"];
    };
    defaultApplications = {
      "application/pdf" = ["org.gnome.Evince.desktop"];
      "text/plain" = ["org.gnome.gedit.desktop"];
      "text/html" = ["org.mozilla.firefox.desktop"];
      "application/json" = ["org.gnome.gedit.desktop"];
      "application/xml" = ["org.gnome.gedit.desktop"];
      "application/x-shellscript" = ["org.gnome.gedit.desktop"];
      "application/x-perl" = ["org.gnome.gedit.desktop"];
      "application/x-python" = ["org.gnome.gedit.desktop"];
      "application/x-ruby" = ["org.gnome.gedit.desktop"];
      "application/x-php" = ["org.gnome.gedit.desktop"];
      "application/x-java" = ["org.gnome.gedit.desktop"];
      "application/x-javascript" = ["org.gnome.gedit.desktop"];
      "video/mp4" = ["mpv.desktop"];
      "video/x-matroska" = ["mpv.desktop"];
      "video/webm" = ["mpv.desktop"];
      "audio/mpeg" = ["mpv.desktop"];
      "audio/ogg" = ["mpv.desktop"];
      "audio/wav" = ["mpv.desktop"];
      "audio/flac" = ["mpv.desktop"];
      "image/bmp" = ["feh.desktop"];
      "image/gif" = ["feh.desktop"];
      "image/jpeg" = ["feh.desktop"];
      "image/png" = ["feh.desktop"];
      "image/svg+xml" = ["feh.desktop"];
      "image/tiff" = ["feh.desktop"];
      "application/zip" = ["org.gnome.FileRoller.desktop"];
      "application/x-rar" = ["org.gnome.FileRoller.desktop"];
      "application/x-7z-compressed" = ["org.gnome.FileRoller.desktop"];
      "application/x-tar" = ["org.gnome.FileRoller.desktop"];
      "application/x-gzip" = ["org.gnome.FileRoller.desktop"];
      "application/x-bzip2" = ["org.gnome.FileRoller.desktop"];
    };
  };
}

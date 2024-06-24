{pkgs, ...}:
{

    #spotiblock = prev.spotify.overrideAttrs (_old: rec {
    #  postInstall = ''
    #    ExecMe="env LD_PRELOAD=${prev.spotify-adblock}/lib/libspotifyadblock.so spotify"
    #    sed -i "s|^TryExec=.*|TryExec=$ExecMe %U|" $out/share/applications/spotify.desktop
    #    sed -i "s|^Exec=.*|Exec=$ExecMe %U|" $out/share/applications/spotify.desktop
    #  '';
    #});
  xdg.desktopEntries."spotify-adblock" = {
    name = "Spotify (Adblock)";
    comment = "Spotify with Adblock";
    icon = "spotify";
    exec = "env LD_PRELOAD=${pkgs.spotify-adblock}/lib/libspotifyadblock.so ${pkgs.spotify}/bin/spotify";
    categories = [ "Audio" "Music" "Player" ];
    terminal = false;
  };

  # gnome settings app
  xdg.desktopEntries."org.gnome.Settings" = {
    name = "Settings";
    comment = "Gnome Control Center";
    icon = "org.gnome.Settings";
    exec = "env XDG_CURRENT_DESKTOP=gnome ${pkgs.gnome.gnome-control-center}/bin/gnome-control-center";
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
    gnome.gnome-disk-utility

    #gedit
    f3d


    gimp
    mpv
    feh
  ];

  # XDG settings
  xdg.mimeApps = {
    enable = true;
    defaultApplications = {
      "application/pdf" = ["org.gnome.Evince.desktop"];
      "text/plain" = ["kitty-neovim.desktop"];
      "text/html" = ["org.mozilla.firefox.desktop"];
      "application/json" = ["kitty-neovim.desktop"];
      "application/xml" = ["kitty-neovim.desktop"];
      "application/x-shellscript" = ["kitty-neovim.desktop"];
      "application/x-perl" = ["kitty-neovim.desktop"];
      "application/x-python" = ["kitty-neovim.desktop"];
      "application/x-ruby" = ["kitty-neovim.desktop"];
      "application/x-php" = ["kitty-neovim.desktop"];
      "application/x-java" = ["kitty-neovim.desktop"];
      "application/x-javascript" = ["kitty-neovim.desktop"];
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

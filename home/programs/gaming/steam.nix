{pkgs, ...}: {
  home.packages = with pkgs; [
    #steam-with-pkgs
    #steam
    #steam-tui
    #steamcmd
    #gamescope
    #protontricks
  ];
}
# package installation, Steam, libraries


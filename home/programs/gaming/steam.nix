{pkgs, ...}: {
  home.packages = with pkgs; [
    #steam-with-pkgs
    #steam
    #steam-tui
    #steamcmd
    #gamescope
    #protontricks
  ];
  programs.steam.enable = true;
}
# package installation, Steam, libraries


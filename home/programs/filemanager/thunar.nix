{ pkgs, ... }:
{
  home.packages = with pkgs; [
    xfce.thunar
    xfce.thunar-archive-plugin
    #xfce.thunar-media-tags-plugin
    #xfce.thunar-volman
    #xfce.thunar-vcs-plugin
    #xfce.thunar-shares-plugin
    #xfce.thunar-dropbox-plugin
    #xfce.thunar-wallpaper-plugin
  ];

  # add other services that intigrate with thunar
  # to allow unziping and other file operations



}

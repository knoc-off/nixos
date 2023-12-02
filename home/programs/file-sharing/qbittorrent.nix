#NixOS, package installation, qBittorrent, torrenting application.
{pkgs, config, libs, ... }:
{
  home.packages = with pkgs; [
    qbittorent
  ];
}

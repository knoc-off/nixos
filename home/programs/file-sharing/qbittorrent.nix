#NixOS, package installation, qBittorrent, torrenting application.
{
  pkgs,
  ...
}: {
  home.packages = with pkgs; [
    qbittorent
  ];
}

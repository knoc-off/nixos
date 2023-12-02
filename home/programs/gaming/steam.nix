{ pkgs, lib, ... }:
let
  steam-with-pkgs = pkgs.steam.override {
    extraPkgs = pkgs: with pkgs; [
      xorg.libXcursor
      xorg.libXi
      xorg.libXinerama
      xorg.libXScrnSaver
      libpng
      libpulseaudio
      libvorbis
      stdenv.cc.cc.lib
      libkrb5
      keyutils
      glibc
    ];
  };
in
{
  home.packages = with pkgs; [
    #steam-with-pkgs
    steam
    steam-tui
    steamcmd
    gamescope
    protontricks
  ];


}
# package installation, Steam, libraries

{ config, pkgs, lib, ... }:
{
  programs.eww.enable = true;
  programs.eww.configDir = ./eww;

  programs.eww.package = pkgs.eww-wayland;

}

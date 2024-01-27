{ config, pkgs, lib, ... }:
{

  programs.eww = {
    package = pkgs.eww-wayland;

    enable = true;
  #  configDir = ./eww;
  };



  #  home.file =
  #    let
  #      dir = "eww";
  #    in
  #    {
  #      "${dir}/eww.yuck" = {
  #        text = ''
  #
  #safasf asf
  #
  #      '';
  #      };
  #      "${dir}/eww.scss" = {
  #        text = ''
  #          @import "eww";
  #
  #          @include eww;
  #        '';
  #      };
  #
  #    };



}

# Neovim configuration built via nixvim
{
  lib,
  pkgs,
  inputs,
  vimUtils,
  fetchFromGitHub,
}: let
  myLib = import ../../lib {inherit lib;};
  inherit (myLib) color-lib math;
  theme = import ../../theme.nix {inherit lib color-lib;};

  neovim-plugins = import ../neovim-plugins {inherit vimUtils fetchFromGitHub;};

  customPkgs = import inputs.nixpkgs-unstable {
    system = pkgs.stdenv.hostPlatform.system;
    config = {
      allowUnfree = true;
    };
    overlays = [
      inputs.nixneovimplugins.overlays.default
      neovim-plugins.overlay
    ];
  };

  nixvim = inputs.nixvim.legacyPackages.${pkgs.stdenv.hostPlatform.system};

  mkNeovim = configModule:
    nixvim.makeNixvimWithModule {
      pkgs = customPkgs;
      extraSpecialArgs = {inherit color-lib theme;};
      module = {
        imports = [configModule];
      };
    };
in {
  default = mkNeovim ./configurations/minimal.nix;
}

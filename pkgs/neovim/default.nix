# Neovim configuration built via nixvim
{
  lib,
  pkgs,
  inputs,
  vimUtils,
  fetchFromGitHub,
}:
let
  myLib = import ../../lib { inherit lib; };
  inherit (myLib) color-lib math rustAnalyzerSettings;
  theme = import ../../theme.nix { inherit lib color-lib; };

  neovim-plugins = import ./plugins-overlay.nix { inherit vimUtils fetchFromGitHub; };

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
in
nixvim.makeNixvimWithModule {
  pkgs = customPkgs;
  extraSpecialArgs = { inherit color-lib theme rustAnalyzerSettings; };
  module = {
    imports = [ ./configurations/minimal.nix ];
  };
}

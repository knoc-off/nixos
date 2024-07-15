{
  description = "A nixvim configuration";

  inputs = {
    nixvim.url = "github:nix-community/nixvim";
    flake-utils.url = "github:numtide/flake-utils";
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    nixneovimplugins.url = "github:NixNeovim/nixpkgs-vim-extra-plugins";
  };

  outputs = {
    nixpkgs,
    nixvim,
    flake-utils,
    nixneovimplugins,
    ...
  } @ inputs:
    flake-utils.lib.eachDefaultSystem (system: let

      nixvimLib = nixvim.lib.${system};

      pkgs = import nixpkgs {
        inherit system;
        config = {allowUnfree = true;};
        overlays = [nixneovimplugins.overlays.default];
      };

      nixvim' = nixvim.legacyPackages.${system};

      default = let
        config = import ./configurations;
      in
      nixvim'.makeNixvimWithModule {
        inherit pkgs;
        #module = ./config/default.nix;
        module = config;
      };

    in {
      checks = {
        # Run `nix flake check .` to verify that your config is not broken
        default = nixvimLib.check.mkTestDerivationFromNvim {
          inherit default;
          name = "default config";
        };
      };

      packages = {
        # Lets you run `nix run .` to start nixvim
        default = default;
      };
    });
}

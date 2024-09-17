{
  description = "A declarative Nix config";

  inputs = {
    # Nixpkgs
    nixpkgs.url = "github:nixos/nixpkgs/nixos-24.05";
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";

    # nix cli
    nixos-cli.url = "github:water-sucks/nixos";

    # Rust overlay
    rust-overlay.url = "github:oxalica/rust-overlay";

    # my custom website
    mywebsite.url = "github:knoc-off/Website";

    # Home Manager
    home-manager = {
      url = "github:nix-community/home-manager/release-24.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixvim.url = "github:nix-community/nixvim";
    nixneovimplugins.url = "github:NixNeovim/nixpkgs-vim-extra-plugins";

    # Hardware-specific configurations
    hardware.url = "github:nixos/nixos-hardware";

    # Disko - declarative disk partitioning
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Secure boot
    lanzaboote.url = "github:nix-community/lanzaboote";

    # NixOS generators
    nixos-generators = {
      url = "github:nix-community/nixos-generators";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Neovim config
    neovim = {
      url = "github:knoc-off/neovim-config";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };

    # Firefox add-ons
    firefox-addons = {
      url = "gitlab:rycee/nur-expressions?dir=pkgs/firefox-addons";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Hyprland
    #hyprland.url = "github:hyprwm/hyprland";
    hyprland.url = "git+https://github.com/hyprwm/Hyprland?submodules=1";
    hyprland-plugins = {
      url = "github:hyprwm/hyprland-plugins";
      inputs.hyprland.follows = "hyprland";
    };

    # add ags / Widgets, etc.
    ags.url = "github:Aylur/ags";

    # Secrets management
    sops-nix.url = "github:Mic92/sops-nix";

    # poetry2nix
    poetry2nix = {
      url = "github:nix-community/poetry2nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Minecraft servers and packages
    nix-minecraft.url = "github:Infinidoge/nix-minecraft";

    # Non-Flake Inputs:

    firefox-csshacks = {
      url = "github:MrOtherGuy/firefox-csshacks";
      flake = false;
    };


  };

  nixConfig = {
    extra-substituters = [ "https://nix-community.cachix.org" ];
    extra-trusted-public-keys = [
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      "hyprland.cachix.org-1:a7pgxzMz7+chwVL3/pzj6jIBMioiJM7ypFP8PwtkuGc="
    ];
  };

  outputs = inputs@{ self, nixpkgs, home-manager, ... }:
    let

      theme = import ./theme.nix;

      systems = [
        "aarch64-linux"
        "i686-linux"
        "x86_64-linux"
        "aarch64-darwin"
        "x86_64-darwin"
      ];

      forAllSystems = nixpkgs.lib.genAttrs systems;

      inherit (self) outputs;

      lib = nixpkgs.lib.extend (final: prev: home-manager.lib);

      inherit (lib) nixosSystem genAttrs hasPrefix listToAttrs;

      mkHost = hostname: username: system: {
        name = hostname;
        value = nixosSystem {
          specialArgs = {
            inherit self # this does the same as outputs
              inputs outputs # this does the same as self
              hostname username lib

              system theme # remove this.
            ;
            selfPkgs = self.packages.${system};
          };
          modules = [
            {
              nixpkgs.hostPlatform = system;
              nixpkgs.buildPlatform = "x86_64-linux";
            }
            ./systems/${hostname}.nix
          ];
        };
      };

      mkPkgShell = system: shell:
        let
          pkgs = import nixpkgs {
            inherit system;
            config.allowUnfree = true;
          };
        in
        import ./pkgs {
          inherit inputs self system pkgs shell;
        };

    in rec {
      packages = forAllSystems (system: mkPkgShell system false);
      devShells = forAllSystems (system: mkPkgShell system true);

      nixosModules = import ./modules/nixos/default.nix;

      overlays = import ./overlays { inherit inputs; };


      images = {
        rpi3A = nixosConfigurations.rpi3A.config.system.build.sdImage;
        rpi3B = nixosConfigurations.rpi3B.config.system.build.sdImage;
        laptop = nixosConfigurations.laptop-iso.config.system.build.isoImage;
      };

      nixosConfigurations = listToAttrs [
        (mkHost "framework13" "knoff" "x86_64-linux")
        (mkHost "hetzner" "knoff" "x86_64-linux")
      ];

    };
}

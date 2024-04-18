{
  description = "A decaratve nix config";

  nixConfig = {
    extra-substituters = [
      "https://nix-community.cachix.org"
    ];
    extra-trusted-public-keys = [
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      "hyprland.cachix.org-1:a7pgxzMz7+chwVL3/pzj6jIBMioiJM7ypFP8PwtkuGc="
    ];
  };

  inputs = {
    # color scheme
    themes.url = "github:RGBCube/ThemeNix";

    sops-nix.url = "github:Mic92/sops-nix";

    # Disko - a declarative disk partitioning tool
    disko.url = "github:nix-community/disko";
    disko.inputs.nixpkgs.follows = "nixpkgs";

    # Build ISO files for live booting, etc.
    nixos-generators = {
      url = "github:nix-community/nixos-generators";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # my neovim config
    nixvim-flake.url = "github:knoc-off/neovim-config";

    #nixpkgs.url = "github:nixos/nixpkgs/nixos-23.05";
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    # Firefox add-ons packaged for Nix
    firefox-addons = {
      url = "gitlab:rycee/nur-expressions?dir=pkgs/firefox-addons";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Hyprland
    hyprland.url = "github:hyprwm/hyprland";
    hyprland-plugins.url = "github:hyprwm/hyprland-plugins";
    hyprland-plugins.inputs.hyprland.follows = "hyprland";

    # Home Manager (for managing user environments using Nix)
    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    # NixOS hardware-specific configurations
    hardware.url = "github:nixos/nixos-hardware";

    # TPM
    lanzaboote.url = "github:nix-community/lanzaboote";


    # experimental things:
    #nuenv.url = "github:DeterminateSystems/nuenv";

  };

  outputs =
    inputs @ { self
    , themes
    , nixpkgs
    , home-manager
    , disko
    , nixos-generators
    , ...
    }:
    let
      inherit (self) outputs;

      # Supported systems for your flake packages, shell, etc.
      systems = [
        "aarch64-linux"
        "i686-linux"
        "x86_64-linux"
        "aarch64-darwin"
        "x86_64-darwin"
      ];
      # This is a function that generates an attribute by calling a function you
      # pass to it, with each system as an argument
      forAllSystems = nixpkgs.lib.genAttrs systems;

      system = "x86_64-linux";
      #pkgs = import nixpkgs {
      #  system = "x86_64-linux";
      #  config.allowUnfree = true;
      #};

      # theme
      theme = themes.custom (import ./theme.nix);
    in
    rec
    {

      # custom packages
      packages = forAllSystems (system: import ./pkgs nixpkgs.legacyPackages.${system});

      # Your custom packages and modifications, exported as overlays
      overlays = import ./overlays {
        inherit inputs;
      };

      images.rpi3A = nixosConfigurations.rpi3A.config.system.build.sdImage;

      # This is problomatic, need to override disko or something.
      images.laptop = nixosConfigurations.laptop.config.system.build.isoImage;

      nixosConfigurations = {
        # should rename to framework13 or something similar.
        framework13 = nixpkgs.lib.nixosSystem {
          specialArgs = { inherit inputs outputs; };
          system = "x86_64-linux";
          modules = [
            # main entry into the system
            ./systems/framework13.nix

            # hardware for my laptop
            inputs.hardware.nixosModules.framework-13-7040-amd

            { boot.binfmt.emulatedSystems = [ "aarch64-linux" ]; }

            # Disko
            disko.nixosModules.disko
            { disko.devices.disk.vdb.device = "/dev/nvme0n1"; }
            ./systems/hardware/disks/btrfs-luks.nix


            # Home-Manager Config
            home-manager.nixosModules.home-manager
            {
              home-manager.useGlobalPkgs = false;
              home-manager.useUserPackages = true;
              home-manager.users.knoff = import ./home/knoff-laptop.nix;
              home-manager.extraSpecialArgs = {
                inherit inputs;
                inherit outputs;
                inherit system;
                inherit theme;
              };
            }
          ];
        };

        # hetzner-cloud server.
        hetzner-cloud = nixpkgs.lib.nixosSystem {
          specialArgs = { inherit inputs outputs; };
          system = "x86_64-linux";
          modules = [
            ./systems/hetzner-server.nix
          ];
        };

        rpi3A = nixpkgs.lib.nixosSystem {
          specialArgs = { inherit inputs outputs; };
          system = "aarch64-linux";
          modules = [
            "${nixpkgs}/nixos/modules/installer/sd-card/sd-image-aarch64.nix"

            # the disk im installing onto, should maybe move the actual path here too?
            disko.nixosModules.disko
            { disko.devices.disk.vdb.device = "/dev/mmcblk0"; }

            ./systems/raspberry3A.nix
            {
              nixpkgs.config.allowUnsupportedSystem = true;
              #nixpkgs.hostPlatform.system = "armv7l-linux";
              nixpkgs.hostPlatform.system = "aarch64-linux";
              #nixpkgs.buildPlatform.system = "x86_64-linux";
            }
          ];
        };
      };
    };
}

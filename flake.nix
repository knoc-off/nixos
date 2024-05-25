{
  description = "A declarative Nix config";

  inputs = {
    # Nixpkgs
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    # my custom website
    mywebsite.url = "github:knoc-off/Website";

    # Solara, my custom flake. pkgs, modules, etc.
    solara.url = "github:knoc-off/solara";
    solara.inputs.nixpkgs.follows = "nixpkgs";

    # Home Manager
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Hardware-specific configurations
    hardware.url = "github:nixos/nixos-hardware";

    # Color scheme
    themes.url = "github:RGBCube/ThemeNix";

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
    nixvim-flake.url = "github:knoc-off/neovim-config";

    # Firefox add-ons
    firefox-addons = {
      url = "gitlab:rycee/nur-expressions?dir=pkgs/firefox-addons";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Hyprland
    hyprland.url = "github:hyprwm/hyprland";
    hyprland-plugins = {
      url = "github:hyprwm/hyprland-plugins";
      inputs.hyprland.follows = "hyprland";
    };

    # Secrets management
    sops-nix.url = "github:Mic92/sops-nix";
  };

  nixConfig = {
    extra-substituters = [
      "https://nix-community.cachix.org"
    ];
    extra-trusted-public-keys = [
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      "hyprland.cachix.org-1:a7pgxzMz7+chwVL3/pzj6jIBMioiJM7ypFP8PwtkuGc="
    ];
  };

  outputs = inputs @ { self, solara, nixpkgs, home-manager, disko, ... }:
    let
      inherit (self) outputs;
      theme = inputs.themes.custom (import ./theme.nix);

      systems = [
        "aarch64-linux"
        "i686-linux"
        "x86_64-linux"
        "aarch64-darwin"
        "x86_64-darwin"
      ];

      forAllSystems = nixpkgs.lib.genAttrs systems;
    in
    rec {
      packages = forAllSystems (system: import ./pkgs nixpkgs.legacyPackages.${system});

      overlays = import ./overlays { inherit inputs; };

      images = {
        rpi3A = nixosConfigurations.rpi3A.config.system.build.sdImage;
      };

      nixosConfigurations = {
        framework13 = nixpkgs.lib.nixosSystem {
          specialArgs = { inherit inputs outputs; inherit (solara) nixosModules homeManagerModules; };
          system = "x86_64-linux";
          modules = [
            ./systems/framework13.nix
            inputs.hardware.nixosModules.framework-13-7040-amd
            { boot.binfmt.emulatedSystems = [ "aarch64-linux" ]; }

            {
              boot.lanzaboote = {
                enable = nixpkgs.lib.mkDefault true;
                pkiBundle = "/etc/secureboot";
              };
            }

            disko.nixosModules.disko
            { disko.devices.disk.vdb.device = "/dev/nvme0n1"; }
            ./systems/hardware/disks/btrfs-luks.nix
            home-manager.nixosModules.home-manager
            {
              home-manager.useGlobalPkgs = false;
              home-manager.useUserPackages = true;
              home-manager.users.knoff = import ./home/knoff-laptop.nix;
              home-manager.extraSpecialArgs = {
                inherit inputs outputs theme;
                system = "x86_64-linux";
              };
            }
          ];
        };

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
            ./systems/raspberry3A.nix
            {
              nixpkgs.config.allowUnsupportedSystem = true;
              nixpkgs.hostPlatform.system = "aarch64-linux";
            }
          ];
        };


        laptop-iso = nixpkgs.lib.nixosSystem {
          specialArgs = { inherit inputs outputs; };
          system = "x86_64-linux";
          modules = [
            "${nixpkgs}/nixos/modules/installer/cd-dvd/iso-image.nix"
            ./systems/framework13.nix
            {
              # Define a minimal disk layout for the laptop ISO
              boot.loader.grub.device = "/dev/sda";
              fileSystems."/" = {
                device = "/dev/sda1";
                fsType = "ext4";
              };
            }
           {
             isoImage = {
              isoName = "laptop-image.iso";
              volumeID = "NIXOS_LIVE";
              # Set the size of the ISO image (in megabytes)
            };
          }
          ];
        };
      };
      images.laptop = nixosConfigurations.laptop-iso.config.system.build.isoImage;
    };
}


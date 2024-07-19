{
  description = "A declarative Nix config";

  inputs = {
    # Nixpkgs
    nixpkgs.url = "github:nixos/nixpkgs/nixos-24.05";
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";

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

    # Secrets management
    sops-nix.url = "github:Mic92/sops-nix";

    # Minecraft servers and packages
    nix-minecraft.url = "github:Infinidoge/nix-minecraft";
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
      inherit (self) outputs;
      theme = import ./theme.nix;

      systems = [
        "aarch64-linux"
        "i686-linux"
        "x86_64-linux"
        "aarch64-darwin"
        "x86_64-darwin"
      ];

      forAllSystems = nixpkgs.lib.genAttrs systems;
    in rec {
      #packages = forAllSystems (system: import ./pkgs nixpkgs.legacyPackages.${system});

      packages = forAllSystems (system:
        import ./pkgs {
          inherit inputs;
          pkgs = nixpkgs.legacyPackages.${system};
        });

      overlays = import ./overlays { inherit inputs; };

      devShells = forAllSystems (system:
        import ./devshells {
          inherit inputs;
          pkgs = nixpkgs.legacyPackages.${system};
        });

      images = {
        rpi3A = nixosConfigurations.rpi3A.config.system.build.sdImage;
        rpi3B = nixosConfigurations.rpi3B.config.system.build.sdImage;
      };

      nixosConfigurations = {
        framework13 = nixpkgs.lib.nixosSystem {
          specialArgs = { inherit inputs outputs; };
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

            inputs.disko.nixosModules.disko
            { disko.devices.disk.vdb.device = "/dev/nvme0n1"; }
            ./systems/hardware/disks/btrfs-luks.nix
            home-manager.nixosModules.home-manager
            {
              home-manager = {
                useGlobalPkgs = false;
                useUserPackages = true;
                users.knoff = import ./home/knoff-laptop.nix;
                extraSpecialArgs = {
                  inherit inputs outputs theme;
                  system = "x86_64-linux";
                };
              };
            }
          ];
        };

        nuci5 = nixpkgs.lib.nixosSystem {
          specialArgs = { inherit inputs outputs; };
          system = "x86_64-linux";
          modules = [
            ./systems/nuci5.nix

            inputs.hardware.nixosModules.common-cpu-intel

            inputs.disko.nixosModules.disko
            ./systems/hardware/disks/disk-module.nix
            {
              diskoCustom = {
                bootType = "efi"; # Choose "bios" or "efi"
                swapSize = "12G"; # Size of the swap partition
                diskDevice = "/dev/sda"; # The disk device to configure
              };
              #disko.devices.disk.vdb.device = "/dev/disk/by-id/wwn-0x502b2a201d1c1b1a";
            }

            #./systems/hardware/disks/btrfs-luks.nix

            home-manager.nixosModules.home-manager
            {
              home-manager = {
                useGlobalPkgs = false;
                useUserPackages = true;
                users.knoff = import ./home/knoff-laptop.nix;
                extraSpecialArgs = {
                  inherit inputs outputs theme;
                  system = "x86_64-linux";
                };
              };
            }
          ];
        };

        home-server = nixpkgs.lib.nixosSystem {
          specialArgs = { inherit inputs outputs; };
          system = "x86_64-linux";
          modules = [
            ./systems/home-server.nix

            #inputs.hardware.nixosModules.lenovo-thinkpad-x1-6th-gen

            # Disko
            inputs.disko.nixosModules.disko
            #./systems/hardware/disks/simple-disk.nix
            ./systems/hardware/disks/disk-module.nix
            {
              diskoCustom = {
                bootType = "bios"; # Choose "bios" or "efi"
                swapSize = "12G"; # Size of the swap partition
                diskDevice = "/dev/sda"; # The disk device to configure
              };
              #disko.devices.disk.vdb.device = "/dev/disk/by-id/wwn-0x502b2a201d1c1b1a";
            }
          ];
        };

        hetzner-cloud = nixpkgs.lib.nixosSystem {
          specialArgs = { inherit inputs outputs; };
          system = "x86_64-linux";
          modules = [ ./systems/hetzner-server.nix ];
        };

        rpi3B = nixpkgs.lib.nixosSystem {
          specialArgs = { inherit inputs outputs; };
          system = "aarch64-linux";
          modules = [
            "${nixpkgs}/nixos/modules/installer/sd-card/sd-image-aarch64.nix"
            ./systems/raspberry3B.nix
            {
              nixpkgs.config.allowUnsupportedSystem = true;
              nixpkgs.hostPlatform.system = "aarch64-linux";
            }
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
      images.laptop =
        nixosConfigurations.laptop-iso.config.system.build.isoImage;
    };
}

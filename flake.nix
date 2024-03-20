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
    # experimental, not sure if good idea.
    #fprint = {
    #  url = "github:ahbnr/nixos-06cb-009a-fingerprint-sensor";
    #  inputs.nixpkgs.follows = "nixpkgs";
    #};

    # Disko - a declarative disk partitioning tool
    disko.url = "github:nix-community/disko";
    disko.inputs.nixpkgs.follows = "nixpkgs";

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

    # Pyprland, python plugins for Hyprland
    # pyprland.url = "github:hyprland-community/pyprland";
    # https://github.com/hyprland-community/pyprland/blob/main/flake.nix

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
    {

      # custom packages
      packages = forAllSystems (system: import ./pkgs nixpkgs.legacyPackages.${system});


      # Your custom packages and modifications, exported as overlays
      overlays = import ./overlays {
        inherit inputs;
      };

      nixosConfigurations = {
        laptop = nixpkgs.lib.nixosSystem {
          specialArgs = { inherit inputs outputs; };
          system = "x86_64-linux";
          modules = [
            # main entry into the system
            ./systems/laptop.nix

            # the disk im installing onto, should maybe move the actual path here too?
            disko.nixosModules.disko
            { disko.devices.disk.vdb.device = "/dev/nvme0n1"; }

            # The Home-Manager Config
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
      };
    };
}

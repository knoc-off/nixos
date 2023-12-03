{

  description = "A decaratve nix config";


  nixConfig = {
    extra-substituters = [ "https://nix-community.cachix.org" ];
    extra-trusted-public-keys = [
      # cachix
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      # hyprland
      "hyprland.cachix.org-1:a7pgxzMz7+chwVL3/pzj6jIBMioiJM7ypFP8PwtkuGc="
    ];
  };

  inputs = {

    # color scheme
    themes.url = "github:RGBCube/ThemeNix";


    # Disko - a declarative disk partitioning tool
    disko.url = "github:nix-community/disko";
    disko.inputs.nixpkgs.follows = "nixpkgs";

    # my neovim config
    nixvim-flake.url = "github:knoc-off/neovim-config";

    #unstable-packages.url = "github:nixos/nixpkgs/nixos-unstable";
    #nixpkgs.url = "github:nixos/nixpkgs/nixos-23.05";
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    # Firefox add-ons packaged for Nix
    firefox-addons = {
      url = "gitlab:rycee/nur-expressions?dir=pkgs/firefox-addons";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Hyprland
    hyprland.url = "github:hyprwm/hyprland";

    # Home Manager (for managing user environments using Nix)
    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    # NixOS hardware-specific configurations
    hardware.url = "github:nixos/nixos-hardware";

    # TPM
    lanzaboote.url = "github:nix-community/lanzaboote";

  };

  outputs =
    inputs@{ self, themes, nixpkgs, unstable-packages, home-manager, disko, ... }:
    let
      inherit (self) outputs;
      system = "x86_64-linux";

      # theme
      theme = themes.custom ( import ./theme.nix );
    in
    {

      # Your custom packages and modifications, exported as overlays
      #overlays = import ./overlays { inherit inputs; };

      nixosConfigurations = {
        laptop = nixpkgs.lib.nixosSystem {
          specialArgs = { inherit inputs outputs; };
          modules = [
            ./systems/laptop.nix
            disko.nixosModules.disko
            #{ disko.devices.disk.vdb.device = "/dev/sda"; }
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
      };

      homeConfigurations = {
        "knoff/laptop" = home-manager.lib.homeManagerConfiguration {
          pkgs = nixpkgs.legacyPackages.x86_64-linux;
          modules = [
            ./home/knoff-laptop.nix
          ];
          extraSpecialArgs = {
            inherit inputs;
            inherit outputs;
            inherit system;
            inherit theme;
          };
        };

      };

    };
}

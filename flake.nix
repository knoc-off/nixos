{
  description = "A declarative Nix config";
  outputs = inputs @ {
    self,
    nixpkgs,
    nixpkgs-unstable,
    ...
  }: let
    systems = [
      "aarch64-linux"
      "x86_64-linux"
      "aarch64-darwin"
    ];

    forAllSystems = nixpkgs.lib.genAttrs systems;

    inherit (nixpkgs) lib;

    inherit (lib) nixosSystem listToAttrs;

    mkConfig = {
      hostname,
      user,
      system,
      extraModules ? [],
      extraConfigs ? {},
    }: let
      inherit (self.lib) math color-lib;
      theme = import ./theme.nix {inherit color-lib math lib;};

      mkSystem =
        # move this to inputs, override-able
        if lib.strings.hasSuffix "darwin" system
        then inputs.nix-darwin.lib.darwinSystem
        else nixosSystem;
    in
      mkSystem {
        inherit system;
        specialArgs =
          {
            inherit # TODO: i want to phase out all of these. its a mess
              self # needed
              inputs # needed
              hostname # needed
              user # needed
              system # not needed
              theme # not here
              color-lib # not here/not needed
              math # not here/not needed
              lib # this is redundant
              ;
            upkgs = unstablePkgs system;
          }
          // extraConfigs;
        modules =
          [
            ./systems/${hostname}.nix
          ]
          ++ lib.optionals (!lib.strings.hasSuffix "darwin" system) [
            ./systems/modules/commit_message.nix
          ]
          ++ extraModules;
      };

    # Host configuration
    mkHost = hostname: user: system: {
      name = hostname;
      value = mkConfig {
        inherit hostname user system;
      };
    };

    mkImage = hostname: user: system: imageType: rec {
      name = "${hostname}-${imageType}";
      value =
        (mkConfig {
          inherit hostname user system;
          extraModules =
            [
            ]
            ++ (
              if imageType == "isoImage"
              then [
                ./systems/modules/${imageType}.nix
                {isoImage = {isoName = lib.mkForce name;};}
              ]
              else if imageType == "sdImage"
              then [
                ./systems/modules/${imageType}.nix
                {
                  nixpkgs.hostPlatform.system = system;
                  nixpkgs.buildPlatform.system = "x86_64-linux";
                }
              ]
              else [
                ./systems/modules/${imageType}.nix
              ]
            );
        }).config.system.build.${
          imageType
        };
    };

    unstablePkgs = system:
      import nixpkgs-unstable {
        inherit system;
        config = {
          allowUnfree = true;
          android_sdk.accept_license = true;
        };
      };

    mkPkgs = system: let
      upkgs = unstablePkgs system;

      inherit (self.lib) math color-lib;

      theme = import ./theme.nix {inherit color-lib math lib self;};

      pkgs = import nixpkgs {
        inherit system;
        config = {
          allowUnfree = true;
          android_sdk.accept_license = true;
        };
      };
    in
      import ./pkgs {
        # TODO: I want to get rid of color-lib, math, theme - this could be a single module that provides just the color themeing for apps in a sperate file.
        inherit inputs self system pkgs upkgs lib color-lib math theme;
      };
  in {
    packages = forAllSystems mkPkgs;
    devShells = forAllSystems mkPkgs;

    nixosModules = import ./modules/nixos/default.nix;
    homeModules = import ./modules/home/default.nix;
    darwinModules = import ./modules/darwin/default.nix;

    overlays = import ./overlays {inherit inputs;};

    lib = import ./lib {inherit lib;};

    images =
      listToAttrs
      [
        (mkImage "framework13" "knoff" "x86_64-linux" "isoImage")
        (mkImage "raspberry-3b" "knoff" "aarch64-linux" "sdImage")
      ];

    darwinConfigurations = listToAttrs [
      (mkHost "Nicholass-MacBook-Pro" "niko" "aarch64-darwin")
    ];

    nixosConfigurations = listToAttrs [
      (mkHost "framework13" "knoff" "x86_64-linux")
      (mkHost "nuci5" "tv" "x86_64-linux")
      (mkHost "hetzner" "knoff" "x86_64-linux")
    ];
  };

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-25.11";
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";

    nixpkgs-darwin.url = "github:NixOS/nixpkgs/nixpkgs-25.11-darwin";

    nixos-cli.url = "github:water-sucks/nixos";

    rust-overlay.url = "github:oxalica/rust-overlay";

    fenix = {
      url = "github:nix-community/fenix";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };

    home-manager = {
      url = "github:nix-community/home-manager/release-25.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixvim.url = "github:nix-community/nixvim";
    nixneovimplugins.url = "github:NixNeovim/NixNeovimPlugins";

    hardware.url = "github:nixos/nixos-hardware";

    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    lanzaboote.url = "github:nix-community/lanzaboote";

    nixos-generators = {
      url = "github:nix-community/nixos-generators";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    neovim = {
      url = "github:knoc-off/neovim-config";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };

    firefox-addons = {
      url = "gitlab:rycee/nur-expressions?dir=pkgs/firefox-addons";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixgl.url = "github:nix-community/nixGL";

    hyprland.url = "github:hyprwm/Hyprland";
    hyprland-plugins = {
      url = "github:hyprwm/hyprland-plugins";
      inputs.hyprland.follows = "hyprland";
    };

    ags = {
      url = "github:aylur/ags";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    astal.url = "github:Aylur/astal";
    astal.inputs.nixpkgs.follows = "nixpkgs-unstable";

    sops-nix.url = "github:Mic92/sops-nix";

    nix-minecraft.url = "github:Infinidoge/nix-minecraft";

    nix-darwin.url = "github:nix-darwin/nix-darwin/nix-darwin-25.11";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs-darwin";

    zen-browser = {
      url = "github:0xc000022070/zen-browser-flake";
      inputs = {
        # IMPORTANT: To ensure compatibility with the latest Firefox version, use nixpkgs-unstable.
        nixpkgs.follows = "nixpkgs";
        home-manager.follows = "home-manager";
      };
    };

    stylix = {
      url = "github:nix-community/stylix/release-25.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    noctalia = {
      url = "github:noctalia-dev/noctalia-shell";
      inputs = {
        nixpkgs.follows = "nixpkgs";
      };
    };

    noctalia-plugins = {
      url = "github:noctalia-dev/noctalia-plugins";
      flake = false;
    };

    niri = {
      url = "github:sodiboo/niri-flake";

      # this may make the cachix fail.
      inputs = {
        nixpkgs.follows = "nixpkgs";
      };
    };

    firefox-csshacks = {
      url = "github:MrOtherGuy/firefox-csshacks";
      flake = false;
    };
  };

  nixConfig = {
    extra-substituters = ["https://nix-community.cachix.org"];
    extra-trusted-public-keys = [
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
    ];
  };
}

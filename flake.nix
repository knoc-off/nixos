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

    inherit (import ./lib {inherit lib;}) discoverModules discoverPackages;

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

    mkImage = hostname: user: system: imageType: let
      name = "${hostname}-${imageType}";
      imageOverrides =
        {
          isoImage = [{image.fileName = lib.mkForce name;}];
          sdImage = [];
        }.${
          imageType
        } or [
        ];
    in
      lib.nameValuePair name (
        (mkConfig {
          inherit hostname user system;
          extraModules =
            [./systems/modules/${imageType}.nix]
            ++ imageOverrides;
        }).config.system.build.${
          imageType
        }
      );

    unstablePkgs = system:
      import nixpkgs-unstable {
        inherit system;
        config = {
          allowUnfree = true;
          android_sdk.accept_license = true;
        };
      };

    mkPkgs = system: let
      pkgs = import nixpkgs {
        inherit system;
        config = {
          allowUnfree = true;
          android_sdk.accept_license = true;
        };
        overlays = [
          inputs.fenix.overlays.default
          (_final: _prev: {inherit inputs;})
        ];
      };
    in
      discoverPackages pkgs ./pkgs;
  in {
    packages = forAllSystems mkPkgs;
    devShells = forAllSystems mkPkgs;

    nixosModules = discoverModules ./modules/nixos;
    homeModules = discoverModules ./modules/home;
    darwinModules = discoverModules ./modules/darwin;

    overlays = import ./overlays {inherit inputs;};

    lib = import ./lib {inherit lib;};

    images =
      listToAttrs
      [
        (mkImage "minimal" "default" "x86_64-linux" "isoImage")
        (mkImage "framework13" "knoff" "x86_64-linux" "isoImage")
        (mkImage "rpi-3a-plus" "root" "aarch64-linux" "sdImage")
      ];

    darwinConfigurations = listToAttrs [
      # (mkHost "Nicholass-MacBook-Pro" "niko" "aarch64-darwin")
    ];

    nixosConfigurations = listToAttrs [
      (mkHost "framework13" "knoff" "x86_64-linux")
      (mkHost "thinkpad-work" "niko" "x86_64-linux")
      (mkHost "nuci5" "tv" "x86_64-linux")
      (mkHost "hetzner" "knoff" "x86_64-linux")
      (mkHost "rpi-3a-plus" "root" "aarch64-linux")
    ];
  };

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-25.11";
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";

    nixpkgs-darwin.url = "github:NixOS/nixpkgs/nixpkgs-25.11-darwin";

    nixos-cli.url = "github:water-sucks/nixos";

    rust-overlay.url = "github:oxalica/rust-overlay";

    crane.url = "github:ipetkov/crane";

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

    hyprnix.url = "github:hyprwm/hyprnix";
    hyprland.follows = "hyprnix/hyprland";
    hyprland-plugins = {
      url = "github:hyprwm/hyprland-plugins";
      inputs.hyprland.follows = "hyprland";
    };
    Hyprspace = {
      url = "github:KZDKM/Hyprspace";
      inputs.hyprland.follows = "hyprland";
    };
    hyprqt6engine = {
      url = "github:hyprwm/hyprqt6engine";
      inputs.nixpkgs.follows = "hyprnix/nixpkgs";
      inputs.hyprutils.follows = "hyprnix/hyprutils";
      inputs.hyprlang.follows = "hyprnix/hyprlang";
      inputs.systems.follows = "hyprnix/systems";
    };

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

    NixVirt = {
      url = "github:AshleyYakeley/NixVirt";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    UnattendedWinstall = {
      url = "github:memstechtips/UnattendedWinstall";
      flake = false;
    };

    determinate.url = "https://flakehub.com/f/DeterminateSystems/determinate/*";

    firefox-csshacks = {
      url = "github:MrOtherGuy/firefox-csshacks";
      flake = false;
    };

    nelly = {
      url = "github:nelly-solutions/nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  nixConfig = {
    extra-substituters = [
      "https://nix-community.cachix.org"
      "https://crane.cachix.org"
    ];
    extra-trusted-public-keys = [
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      "crane.cachix.org-1:8Scfpmn9w+hGdXH/Q9tTLiYAE/2dnJYRJP7kl80GuRk="
    ];
  };
}

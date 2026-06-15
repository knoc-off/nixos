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

    inherit (import ./lib {inherit lib;}) discoverModules discoverPackages discoverAspects;

    aspects = discoverAspects {inherit inputs self;} ./modules;

    mkConfig = {
      hostname,
      system,
      extraModules ? [],
      extraConfigs ? {},
    }: let
      mkSystem =
        if lib.strings.hasSuffix "darwin" system
        then inputs.nix-darwin.lib.darwinSystem
        else nixosSystem;
    in
      mkSystem {
        inherit system;
        specialArgs =
          {
            inherit
              self
              inputs
              ;
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
    mkHost = hostname: system: {
      name = hostname;
      value = mkConfig {
        inherit hostname system;
      };
    };

    mkImage = hostname: system: imageType: let
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
          inherit hostname system;
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
      upkgs = unstablePkgs system;
      pkgs = import nixpkgs {
        inherit system;
        config = {
          allowUnfree = true;
          android_sdk.accept_license = true;
        };
        overlays = [
          inputs.fenix.overlays.default
          (_final: _prev: {inherit inputs upkgs;})
        ];
      };
    in
      discoverPackages pkgs ./pkgs;
  in {
    packages = forAllSystems mkPkgs;
    devShells = forAllSystems (
      system: let
        pkgs = mkPkgs system;
        # Recursively prefer passthru.devShell where available.
        preferShell = lib.mapAttrs (
          _: v:
            if v ? devShell
            then v.devShell
            else if lib.isAttrs v && !(lib.isDerivation v)
            then preferShell v
            else v
        );
      in
        preferShell pkgs
    );

    nixosModules = aspects.nixos;
    homeModules = aspects.home;
    # darwinModules removed — darwin configs commented out

    overlays = import ./overlays {inherit inputs;};

    lib = import ./lib {inherit lib;};

    images =
      listToAttrs
      [
        (mkImage "minimal" "x86_64-linux" "isoImage")
        (mkImage "framework13" "x86_64-linux" "isoImage")
        (mkImage "rpi-4b-plus" "aarch64-linux" "sdImage")
      ];

    # darwinConfigurations = listToAttrs [
    #   # (mkHost "Nicholass-MacBook-Pro" "aarch64-darwin")
    # ];

    nixosConfigurations = listToAttrs [
      (mkHost "framework13" "x86_64-linux")
      (mkHost "thinkpad-work" "x86_64-linux")
      (mkHost "nuci5" "x86_64-linux")
      (mkHost "hetzner" "x86_64-linux")
      (mkHost "rpi-4b-plus" "aarch64-linux")
    ];
  };

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-26.05";
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";

    # nixpkgs-darwin.url = "github:NixOS/nixpkgs/nixpkgs-26.05-darwin";

    nixos-cli.url = "github:water-sucks/nixos";

    rust-overlay.url = "github:oxalica/rust-overlay";

    crane.url = "github:ipetkov/crane";

    fenix = {
      url = "github:nix-community/fenix";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };

    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
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

    minecraft-modpack = {
      url = "git+ssh://git@github.com/knoc-off/minecraft-modpack.git";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
      inputs.nix-minecraft.follows = "nix-minecraft";
    };

    # nix-darwin.url = "github:nix-darwin/nix-darwin/nix-darwin-26.05";
    # nix-darwin.inputs.nixpkgs.follows = "nixpkgs-darwin";

    zen-browser = {
      url = "github:0xc000022070/zen-browser-flake";
      inputs = {
        # IMPORTANT: To ensure compatibility with the latest Firefox version, use nixpkgs-unstable.
        nixpkgs.follows = "nixpkgs";
        home-manager.follows = "home-manager";
      };
    };

    stylix = {
      url = "github:nix-community/stylix/release-26.05";
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

    jail-nix.url = "sourcehut:~alexdavid/jail.nix";

    claude-code-system-prompts = {
      url = "github:Piebald-AI/claude-code-system-prompts";
      flake = false;
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

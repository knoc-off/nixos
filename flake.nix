{
  description = "A declarative Nix config";
  outputs =
    inputs@{
      self,
      nixpkgs,
      nixpkgs-unstable,
      ...
    }:
    let
      systems = [
        "aarch64-linux"
        "x86_64-linux"
        "aarch64-darwin"
      ];

      forAllSystems = nixpkgs.lib.genAttrs systems;

      inherit (nixpkgs) lib;

      inherit (lib) nixosSystem listToAttrs;

      inherit (import ./lib { inherit lib; })
        discoverPackages
        discoverAspects
        flattenDrvs
        ;

      aspects = discoverAspects { inherit inputs self; } ./modules;

      overlays = import ./overlays { inherit inputs; };

      mkConfig =
        {
          hostname,
          system,
          extraModules ? [ ],
          extraConfigs ? { },
        }:
        let
          mkSystem =
            if lib.strings.hasSuffix "darwin" system then inputs.nix-darwin.lib.darwinSystem else nixosSystem;
        in
        mkSystem {
          inherit system;
          specialArgs = {
            inherit
              self
              inputs
              hostname
              ;
            upkgs = unstablePkgs system;
          }
          // extraConfigs;
          modules = [
            ./systems/${hostname}.nix
            { networking.hostName = lib.mkDefault hostname; }
          ]
          ++ extraModules;
        };

      mkImage =
        hostname: system: imageType:
        let
          name = "${hostname}-${imageType}";
          imageOverrides =
            {
              isoImage = [ { image.fileName = lib.mkForce name; } ];
              sdImage = [ ];
            }
            .${imageType} or [
            ];
        in
        lib.nameValuePair name (
          (mkConfig {
            inherit hostname system;
            extraModules = [ ./systems/modules/${imageType}.nix ] ++ imageOverrides;
          }).config.system.build.${imageType}
        );

      unstablePkgs =
        system:
        import nixpkgs-unstable {
          inherit system;
          config = {
            allowUnfree = true;
            android_sdk.accept_license = true;
          };
        };

      mkPkgs =
        system:
        let
          upkgs = unstablePkgs system;
          pkgs = import nixpkgs {
            inherit system;
            config = {
              allowUnfree = true;
              android_sdk.accept_license = true;
            };
            overlays = [
              inputs.fenix.overlays.default
              overlays.builders
              (_final: _prev: { inherit inputs upkgs; })
            ];
          };
        in
        discoverPackages pkgs ./pkgs;

      # Which of ./pkgs the build farm prebuilds directly, per system.
      #
      # x86_64-linux gets everything meta.platforms says is available: those are
      # built ad-hoc via `nix build`/`nix run` and devShells, not only through a
      # host closure, so they are worth having on their own.
      #
      # aarch64-linux gets nothing directly. rpi-4b-plus is the only aarch64
      # host, and everything it installs -- mqtt-automations via
      # services/home-assistant.nix, caddy-with-plugins via caddy-common --
      # already arrives through toplevel/rpi-4b-plus. Listing packages here as
      # well would only add emulated rebuilds of things nothing installs.
      #
      # null (or a missing entry) means "everything meta says is available".
      cachePackages = {
        aarch64-linux = [ ];
      };

      # What the build farm prebuilds for `system`: the per-host toplevels plus
      # whatever cachePackages allows.
      #
      # The toplevels are the important half. "What will this host try to
      # install" is not something to maintain by hand -- system.build.toplevel
      # already answers it exactly, and transitively. Combined with
      # nix-fast-build --skip-cached, the marginal cost of a toplevel is only
      # its uncached delta: everything reachable from cache.nixos.org is
      # skipped, and what remains is precisely the local packages and patches
      # that are the whole point of the farm.
      mkCacheJobs =
        system:
        let
          # elaborate rather than { system = ...; }: meta.platforms entries may be
          # attrset patterns (lib.systems.inspect.*) as well as plain strings, and
          # matching those needs platform.parsed.
          platform = lib.systems.elaborate system;
          available = lib.filterAttrs (_: lib.meta.availableOn platform) (flattenDrvs (mkPkgs system));

          allow = cachePackages.${system} or null;
          missing = lib.subtractLists (lib.attrNames available) (if allow == null then [ ] else allow);
          packages =
            if allow == null then
              available
            else if missing != [ ] then
              # Loud on purpose: a typo here, or a package whose meta.platforms
              # excludes this system, would otherwise silently build nothing.
              throw
                "cachePackages.${system} names attrs unavailable on ${system}: ${lib.concatStringsSep ", " missing}"
            else
              lib.filterAttrs (name: _: lib.elem name allow) available;

          toplevels = lib.mapAttrs' (
            hostname: _:
            lib.nameValuePair "toplevel/${hostname}"
              nixosConfigurations.${hostname}.config.system.build.toplevel
          ) (lib.filterAttrs (_: hostSystem: hostSystem == system) hosts);
        in
        packages // toplevels;

      # hostname -> system. Single source for both nixosConfigurations and the
      # set of toplevels the build farm prebuilds.
      hosts = {
        framework13 = "x86_64-linux";
        thinkpad-work = "x86_64-linux";
        nuci5 = "x86_64-linux";
        optiplex = "x86_64-linux";
        hetzner = "x86_64-linux";
        rpi-4b-plus = "aarch64-linux";
      };

      nixosConfigurations = lib.mapAttrs (hostname: system: mkConfig { inherit hostname system; }) hosts;
    in
    {
      packages = forAllSystems mkPkgs;
      devShells = forAllSystems (
        system:
        let
          pkgs = mkPkgs system;
          # Recursively prefer passthru.devShell where available.
          preferShell = lib.mapAttrs (
            _: v:
            if v ? devShell then
              v.devShell
            else if lib.isAttrs v && !(lib.isDerivation v) then
              preferShell v
            else
              v
          );
        in
        preferShell pkgs
      );

      nixosModules = aspects.nixos;
      homeModules = aspects.home;
      # darwinModules removed — darwin configs commented out

      inherit overlays;

      lib = import ./lib { inherit lib; };

      images = listToAttrs [
        (mkImage "minimal" "x86_64-linux" "isoImage")
        (mkImage "framework13" "x86_64-linux" "isoImage")
        (mkImage "rpi-4b-plus" "aarch64-linux" "sdImage")
      ];

      # darwinConfigurations = listToAttrs [
      #   # ("Nicholass-MacBook-Pro" "aarch64-darwin")
      # ];

      inherit nixosConfigurations;

      # Everything the optiplex build farm prebuilds and serves. See mkCacheJobs.
      cacheJobs = forAllSystems mkCacheJobs;

      # The hostname -> system table as plain data, so nix-autobuild can learn
      # which `toplevel/*` attrs it must see succeed before publishing without
      # evaluating a single host configuration. Kept in sync by construction:
      # this is the same attrset mkCacheJobs derives the toplevels from.
      hostSystems = hosts;
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
      url = "github:knoc-off/minecraft-modpack";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
      inputs.nix-minecraft.follows = "nix-minecraft";
    };

    # nix-darwin.url = "github:nix-darwin/nix-darwin/nix-darwin-26.05";
    # nix-darwin.inputs.nixpkgs.follows = "nixpkgs-darwin";

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

    determinate.url = "https://flakehub.com/f/DeterminateSystems/determinate/*";

    zen-browser = {
      url = "github:0xc000022070/zen-browser-flake";
      inputs = {
        # IMPORTANT: To ensure compatibility with the latest Firefox version, use nixpkgs-unstable.
        nixpkgs.follows = "nixpkgs";
        home-manager.follows = "home-manager";
      };
    };
    firefox-csshacks = {
      url = "github:MrOtherGuy/firefox-csshacks";
      flake = false;
    };
    fx-autoconfig = {
      url = "github:MrOtherGuy/fx-autoconfig";
      flake = false;
    };
    firefox-addons = {
      url = "gitlab:rycee/nur-expressions?dir=pkgs/firefox-addons";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    jail-nix.url = "sourcehut:~alexdavid/jail.nix";
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

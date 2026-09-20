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
      ];

      forAllSystems = nixpkgs.lib.genAttrs systems;

      inherit (nixpkgs) lib;

      inherit (lib) nixosSystem;

      libExtra = import ./lib { inherit lib; };
      inherit (libExtra) discoverPackages discoverAspects;

      aspects = discoverAspects { inherit inputs self; } ./modules;

      overlays = import ./overlays { inherit inputs; };

      # allowUnfree/android_sdk.accept_license apply identically to both the
      # stable and unstable pkgs instantiations below.
      nixpkgsConfig = {
        allowUnfree = true;
        android_sdk.accept_license = true;
      };

      mkConfig =
        {
          hostname,
          system,
          extraModules ? [ ],
        }:
        nixosSystem {
          inherit system;
          specialArgs = {
            inherit
              self
              inputs
              hostname
              ;
            upkgs = unstablePkgs system;
          };
          modules = [
            ./systems/${hostname}
            { networking.hostName = lib.mkDefault hostname; }
          ]
          ++ extraModules;
        };

      mkImage =
        hostname: system: imageType:
        let
          profiles = {
            isoImage =
              {
                config,
                lib,
                pkgs,
                modulesPath,
                ...
              }:
              {
                imports = [ "${modulesPath}/installer/cd-dvd/installation-cd-minimal.nix" ];
                image.fileName = lib.mkForce "${hostname}-${imageType}";
                boot = {
                  kernelPackages = lib.mkForce pkgs.linuxPackages;
                  initrd.systemd.dbus.enable = true;
                  loader = {
                    systemd-boot.enable =
                      if lib.hasAttr "lanzaboote" config.boot && config.boot.lanzaboote.enable then
                        lib.mkForce false
                      else
                        true;
                    efi.canTouchEfiVariables = true;
                  };
                };
              };
            sdImage =
              { lib, modulesPath, ... }:
              {
                imports = [ "${modulesPath}/installer/sd-card/sd-image-aarch64.nix" ];
                # ZFS is enabled by default in installer profiles but is never cached
                # (built against specific kernel versions). Disable it for SD images.
                boot.supportedFilesystems.zfs = lib.mkForce false;
                # The all-hardware profile includes dw-hdmi which was renamed/removed
                # in newer kernels and doesn't exist in the RPi kernel. Disable it.
                hardware.enableAllHardware = lib.mkForce false;
              };
          };
        in
        (mkConfig {
          inherit hostname system;
          extraModules = [
            self.nixosModules.installer-image
            profiles.${imageType}
          ];
        }).config.system.build.${imageType};

      unstablePkgs =
        system:
        import nixpkgs-unstable {
          inherit system;
          config = nixpkgsConfig;
        };

      mkPkgs =
        system:
        let
          upkgs = unstablePkgs system;
          pkgs = import nixpkgs {
            inherit system;
            config = nixpkgsConfig;
            overlays = [
              inputs.fenix.overlays.default
              overlays.builders
              (_final: _prev: { inherit inputs upkgs self; })
            ];
          };
        in
        discoverPackages pkgs ./pkgs;

      # just iterate over toplevels, build all things that i would need to build
      mkCacheJobs =
        system:
        lib.mapAttrs' (
          hostname: _:
          lib.nameValuePair "toplevel/${hostname}"
            nixosConfigurations.${hostname}.config.system.build.toplevel
        ) (lib.filterAttrs (_: hostSystem: hostSystem == system) hosts);

      # hostname -> system. check if each is a valid arch
      hosts = {
        framework13 = "x86_64-linux";
        thinkpad-work = "x86_64-linux";
        optiplex = "x86_64-linux";
        hetzner = "x86_64-linux";
        rpi-4b-plus = "aarch64-linux";
      };

      nixosConfigurations = lib.mapAttrs (hostname: system: mkConfig { inherit hostname system; }) hosts;
    in
    {
      packages = forAllSystems mkPkgs;

      # `nix flake check` = every package's `passthru.tests` (flattened as
      # <pkg>-<test>) plus the standalone lib checks.
      checks = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          collectTests =
            prefix: attrs:
            lib.concatMapAttrs (
              name: v:
              if lib.isDerivation v then
                lib.mapAttrs' (t: d: lib.nameValuePair "${prefix}${name}-${t}" d) (v.passthru.tests or { })
              else if lib.isAttrs v then
                collectTests "${prefix}${name}-" v
              else
                { }
            ) attrs;
        in
        collectTests "" self.packages.${system}
        // {
          color-lib = import ./lib/color-lib/check.nix { inherit pkgs lib; };
          key-layers = import ./lib/key-layers-check.nix { inherit pkgs self inputs; };
        }
      );

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

      inherit overlays;

      lib = libExtra;

      images = {
        minimal-isoImage = mkImage "minimal" "x86_64-linux" "isoImage";
        rpi-4b-plus-sdImage = mkImage "rpi-4b-plus" "aarch64-linux" "sdImage";
      };

      inherit nixosConfigurations;

      # The per-host toplevels the optiplex build farm prebuilds and serves.
      # See mkCacheJobs.
      cacheJobs = forAllSystems mkCacheJobs;
    };

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-26.05";
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";

    nixos-cli.url = "github:water-sucks/nixos";

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

    # No hyprnix. The whole hypr stack comes from nixpkgs so there is exactly
    # one nixpkgs behind hyprland, its plugins and the portal -- and therefore
    # one libstdc++ and one Qt. Vendoring a second nixpkgs caused real
    # breakage: a Qt 6.10.1/6.10.2 split that segfaulted the share-picker, and
    # a libstdc++ skew that left hyprlang unable to link against its own
    # hyprutils. It also missed the binary cache on every build. The tradeoff
    # is tracking nixpkgs' hyprland instead of upstream HEAD.

    sops-nix.url = "github:Mic92/sops-nix";

    nix-minecraft.url = "github:Infinidoge/nix-minecraft";

    minecraft-modpack = {
      url = "github:knoc-off/minecraft-modpack";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
      inputs.nix-minecraft.follows = "nix-minecraft";
    };

    stylix = {
      url = "github:nix-community/stylix/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # v5 is a native rewrite (meson/C++, OpenGL ES) -- the quickshell/QML era
    # is over, so nothing from the v4 integration carries across: no
    # calendarSupport override, no QML plugins, and settings are TOML with
    # snake_case keys rather than camelCase JSON. Repo also renamed
    # noctalia-shell -> noctalia.
    noctalia = {
      url = "github:noctalia-dev/noctalia/v5.0.0-beta.10";
      inputs = {
        nixpkgs.follows = "nixpkgs";
      };
    };

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

    # Prebuilt `comma`/nix-index database (weekly), used by the jailed
    # opencode toolbelt so `, <program>` works without a first-use index
    # build inside the jail.
    nix-index-database = {
      url = "github:nix-community/nix-index-database";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };

    # opencode plugin consumed straight from the checkout (no build step, it's
    # JS + markdown). Referenced by store path in the jail's opencode config so
    # opencode never npm-installs it at runtime.
    ponytail = {
      url = "github:DietrichGebert/ponytail";
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

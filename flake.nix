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
        (mkConfig {
          inherit hostname system;
          extraModules = [ ./systems/modules/${imageType}.nix ] ++ imageOverrides;
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

      # `nix flake check` runs the color library against its golden fixture.
      # The fixture is static JSON (lib/color-lib/golden.json), so this needs
      # no special evaluator and no network -- just eval.
      checks = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          results = import ./lib/color-lib/tests.nix { inherit lib; };
          inherit (results) summary;

          # A fixture home-manager config exercising every keyLayers feature
          # (bulk capsbinds, per-key actions, raw/cmd escape hatches, a fork,
          # binds, and a non-base layer with classes to dedup/match against).
          # Building it end-to-end through homeManagerConfiguration means
          # this check runs the actual production code path, not a copy.
          keyLayersFixture = inputs.home-manager.lib.homeManagerConfiguration {
              inherit pkgs;
              extraSpecialArgs = { inherit self; };
              modules = [
                self.homeModules.kanata
                self.homeModules.keylayers
                {
                  home.username = "fixture";
                  home.homeDirectory = "/home/fixture";
                  home.stateVersion = "24.05";
                  services.kanata.package = pkgs.kanata-with-cmd;
                  services.kanata.keyboards.main.port = 12345;
                  services.kanata.keyboards.main.extraDefCfg = "danger-enable-cmd yes";
                  keyLayers.enable = true;
                  # `dbl` is always injected in real configs (see
                  # modules/noctalia.nix) and is referenced unconditionally by
                  # every generated `cap-<layer>` alias, so the fixture must
                  # supply it too.
                  keyLayers.extraAliases = ''
                    dbl (tap-dance-eager 250 (XX XX))
                  '';
                  keyLayers.layers = {
                    base.capsbinds = {
                      ctrl = [
                        "a"
                        "b"
                        "c"
                      ];
                      keys.h.key = "left";
                      keys.f5.cmd = "notify-send hello";
                    };
                    browser = {
                      classes = [
                        "firefox"
                        "chromium-browser"
                      ];
                      capsbinds.ctrl = [
                        "a"
                        "c"
                        "f"
                        "t"
                        "v"
                        "w"
                      ];
                      binds.tab = {
                        default = "down";
                        shift = "up";
                      };
                    };
                    terminal = {
                      classes = [
                        "com.mitchellh.ghostty"
                        "foot"
                      ];
                      capsbinds.alt = [ "e" ];
                    };
                  };
                }
              ];
            };
        in
        {
          color-lib =
            pkgs.runCommand "color-lib-golden"
              {
                passthru = { inherit (results) summary failures; };
              }
              ''
                ${
                  if summary.fail == 0 && summary.error == 0 then
                    ''echo "color-lib: ${toString summary.pass}/${toString summary.total} passed (${toString summary.known} known divergences, ${toString summary.unsupported} unsupported)"''
                  else
                    ''
                      echo "color-lib: ${toString summary.fail} failed, ${toString summary.error} errored (of ${toString summary.total})" >&2
                      echo "inspect: nix eval --impure --json --expr '(import ./lib/color-lib/tests.nix {}).failures'" >&2
                      exit 1
                    ''
                }
                touch $out
              '';

          # Validates the kanata + Lua fragment generated by lib/key-layers.nix
          # + modules/keylayers against a fixture layer set. Referencing
          # `configFile` forces modules/kanata's own checkPhase (`kanata
          # --check`, using the real upstream parser) to run during this
          # derivation's build; key-layers-check.lua loads the generated Lua
          # fragment (catching syntax errors) and asserts its runtime
          # behavior (class -> layer matching, dedup, base fallback,
          # malformed-event safety) against an in-memory `io.popen`/`hl` stub.
          key-layers =
            pkgs.runCommand "key-layers-check"
              {
                nativeBuildInputs = [ pkgs.lua5_4 ];
                kanataConfig = keyLayersFixture.config.services.kanata.keyboards.main.configFile;
                luaFragment =
                  keyLayersFixture.config.xdg.configFile."hypr/kanata-app-layers.lua".text;
                checkScript = ./lib/key-layers-check.lua;
                passAsFile = [
                  "luaFragment"
                ];
              }
              ''
                # $kanataConfig is only referenced to force its build (and
                # thus modules/kanata's checkPhase) as a dependency; nothing
                # here reads its contents directly.
                : "$kanataConfig"
                lua "$checkScript" "$luaFragmentPath"
                touch $out
              '';
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

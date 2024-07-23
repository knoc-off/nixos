{
  description = "actix-webserver";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    rust-overlay.url = "github:oxalica/rust-overlay";

    # web files:
    wasm-app.url = "github:knoc-off/wasm-flake";
  };

  outputs = { self, nixpkgs, flake-utils, rust-overlay, wasm-app, ... }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        overlays = [ (import rust-overlay) ];
        pkgs = import nixpkgs {
          inherit system overlays;
        };
        rustPlatform = pkgs.makeRustPlatform {
          cargo = pkgs.rust-bin.stable."1.76.0".default;
          rustc = pkgs.rust-bin.stable."1.76.0".default;
        };
        buildInputs = with pkgs; [
          openssl.dev
          pkg-config
          zlib.dev
          alsa-lib
          udev
        ] ++ lib.optionals stdenv.isDarwin (with darwin.apple_sdk.frameworks; [
          libiconv
          CoreServices
          SystemConfiguration
        ]);
      in
      rec {
        packages.actix-web-example = rustPlatform.buildRustPackage {
          pname = "actix-webserver";
          version = "0.1.0";
          src = ./.;
          cargoLock.lockFile = ./Cargo.lock;
          inherit buildInputs;
          nativeBuildInputs = with pkgs; [ pkg-config ];

          # Create a symlink to the generated files from the wasm-app flake
          postInstall = ''
            #mkdir -p $out/static
            ln -s ${wasm-app.defaultPackage.${system}}/lib/ $out/bin/static
          '';
        };

        nixosModules.actix-webserver = { config, lib, pkgs, ... }: {
          systemd.services.actix-webserver = {
            description = "Actix Web Server";
            wantedBy = [ "multi-user.target" ];
            after = [ "network.target" ];
            serviceConfig = {
              ExecStart = "${packages.${pkgs.system}.webserver}/bin/actix-webserver";
              Restart = "always";
              RestartSec = 5;
            };
          };
        };

        defaultPackage = packages.actix-web-example;

        apps.webserver = flake-utils.lib.mkApp {
          drv = packages.actix-web-example;
        };

        defaultApp = apps.webserver;

        devShell = pkgs.mkShell {
          inherit buildInputs;
          nativeBuildInputs = with pkgs; [
            cargo-edit
            cargo-generate
            (rust-bin.stable."1.76.0".default.override {
              extensions = [ "rust-src" ];
            })
            rust-analyzer
            sccache
            pkg-config
          ];
          RUST_BACKTRACE = 1;
        };
      }
    );
}


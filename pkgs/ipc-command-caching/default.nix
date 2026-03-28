{
  lib,
  pkgs,
  fenix,
}: let
  toolchain = fenix.combine [
    fenix.minimal.toolchain
    fenix.default.clippy
  ];
  rustPlatform = pkgs.makeRustPlatform {
    cargo = toolchain;
    rustc = toolchain;
  };
in
  rustPlatform.buildRustPackage {
    pname = "prompt-daemon";
    version = "0.1.0-unstable";

    src = lib.cleanSource ./.;

    nativeBuildInputs = [
      fenix.rust-analyzer
    ];

    postCheck = ''
      cargo clippy --all-targets -- -D warnings
    '';

    cargoLock = {
      lockFile = ./Cargo.lock;
    };

    meta = {
      description = "Pre-computation cache daemon for shell prompt segments";
      license = lib.licenses.mit;
      mainProgram = "prompt-daemon";
    };
  }

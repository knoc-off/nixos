{
  lib,
  pkgs,
  fenix,
}: let
  rustPlatform = pkgs.makeRustPlatform {
    cargo = fenix.minimal.toolchain;
    rustc = fenix.minimal.toolchain;
  };
in
  rustPlatform.buildRustPackage {
    pname = "prompt-daemon";
    version = "0.1.0-unstable";

    src = lib.cleanSource ./.;

    cargoLock = {
      lockFile = ./Cargo.lock;
    };

    meta = {
      description = "Pre-computation cache daemon for shell prompt segments";
      license = lib.licenses.mit;
      mainProgram = "prompt-daemon";
    };
  }

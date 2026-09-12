{
  lib,
  pkgs,
  fenix,
}:
let
  toolchain = fenix.minimal.toolchain;
  rustPlatform = pkgs.makeRustPlatform {
    cargo = toolchain;
    rustc = toolchain;
  };

  prompt-daemon = rustPlatform.buildRustPackage {
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

    passthru.devShell = pkgs.mkShell {
      inputsFrom = [ prompt-daemon ];
      nativeBuildInputs = [
        fenix.rust-analyzer
        fenix.default.clippy
      ];
    };
  };
in
prompt-daemon

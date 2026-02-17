# LSP multiplexer - share language servers between editor instances
# https://codeberg.org/p2502/lspmux
{
  lib,
  pkgs,
  fenix,
}: let
  rustPlatform = pkgs.makeRustPlatform {
    cargo = fenix.minimal.toolchain;
    rustc = fenix.minimal.toolchain;
  };

  src = pkgs.fetchFromGitea {
    domain = "codeberg.org";
    owner = "p2502";
    repo = "lspmux";
    rev = "c096923d20d69a7679b4a0e6c9624fb15070525d";
    hash = "sha256-50j8swerZNwtybIR7wRKZxQlJDipi20ouVTCvyKfE8g=";
  };
in
  rustPlatform.buildRustPackage {
    pname = "lspmux";
    version = "0.3.1-unstable";

    inherit src;

    cargoLock = {
      lockFile = "${src}/Cargo.lock";
    };

    meta = {
      description = "LSP multiplexer - share language servers between editor instances";
      homepage = "https://codeberg.org/p2502/lspmux";
      license = lib.licenses.eupl12;
      mainProgram = "lspmux";
    };
  }

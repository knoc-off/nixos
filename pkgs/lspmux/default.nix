# LSP multiplexer - share language servers between editor instances
# https://codeberg.org/p2502/lspmux
{
  lib,
  pkgs,
  fenix,
}:
let
  rustPlatform = pkgs.makeRustPlatform {
    cargo = fenix.minimal.toolchain;
    rustc = fenix.minimal.toolchain;
  };

  src = pkgs.fetchFromGitea {
    domain = "codeberg.org";
    owner = "p2502";
    repo = "lspmux";
    rev = "18861f9d59e74ece8d867772cf07fa302c2dae98";
    hash = "sha256-OchqUe8GdBPL6tE3zpdaThfhzYZhYluagz1yXiexFT0=";
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

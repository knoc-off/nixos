{
  lib,
  pkgs,
  fenix,
}: let
  wasmToolchain = fenix.combine [
    fenix.complete.toolchain
    fenix.targets.wasm32-unknown-unknown.latest.rust-std
  ];
  rustPlatform = pkgs.makeRustPlatform {
    cargo = wasmToolchain;
    rustc = wasmToolchain;
  };
in
rustPlatform.buildRustPackage {
  pname = "color-lib-wasm";
  version = "0.1.0";
  src = ./.;

  cargoDeps = rustPlatform.fetchCargoVendor {
    src = ./.;
    # Will need updating after Cargo.lock is generated
    hash = "sha256-9KAuNHfNcv8cSrN1GN8y7Ogooo8noXS5XzZJ0KXohT8=";
  };

  CARGO_BUILD_TARGET = "wasm32-unknown-unknown";

  buildPhase = ''
    cargo build --release
  '';

  installPhase = ''
    mkdir -p $out
    wasm-opt -O3 \
      --enable-bulk-memory \
      --enable-nontrapping-float-to-int \
      -o $out/color_lib_wasm.wasm \
      target/wasm32-unknown-unknown/release/color_lib_wasm.wasm
  '';

  nativeBuildInputs = [
    pkgs.binaryen
  ];

  doCheck = false;

  meta = {
    description = "Color manipulation WASM plugin for Nix builtins.wasm (Oklab/Okhsl/Okhsv via palette)";
    license = lib.licenses.mit;
  };
}

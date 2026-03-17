{
  lib,
  pkgs,
  rustPlatform,
}:
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

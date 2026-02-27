{
  lib,
  pkgs,
  rustPlatform,
}:
pkgs.stdenv.mkDerivation {
  pname = "marki-wasm";
  version = "0.2.0";
  src = ./.;

  nativeBuildInputs = [
    pkgs.wasm-pack
    pkgs.wasm-bindgen-cli
    pkgs.binaryen
    pkgs.lld
    rustPlatform.cargoSetupHook
    pkgs.cargo
    pkgs.rustc
  ];

  cargoDeps = rustPlatform.fetchCargoVendor {
    src = ./.;
    hash = "sha256-Qm/FXsF/VBSxIUmOWNDpd/o3QYv4H+Qjw6UF5Xgu0os=";
  };

  # wasm-pack needs HOME for cache, and needs to find wasm-bindgen
  buildPhase = ''
    export HOME=$(mktemp -d)
    wasm-pack build --mode no-install --target no-modules --out-dir pkg
  '';

  installPhase = ''
    mkdir -p $out
    cp pkg/marki.js $out/
    cp pkg/marki_bg.wasm $out/
  '';

  meta = {
    description = "WASM markdown renderer for Anki cards";
    license = lib.licenses.mit;
  };
}

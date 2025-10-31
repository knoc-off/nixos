{
  lib,
  pkgs,
  rustPlatform,
}:
rustPlatform.buildRustPackage rec {
  pname = "marki";
  version = "0.8.5";
  src = ./.;
  useFetchCargoVendor = true;
  # cargoHash = "sha256-XB+MvsF9SUOkVKe1pOGIcsJGA7hYkx0FWfrH1dTGZvA=";
  cargoHash = "sha256-lApy0lyv14F4FoG+qTF3+zUYr0Rl/nJhM11Ux8m2kck=";
  cargoAuditable = null;

  nativeBuildInputs = [
    pkgs.gcc
    pkgs.pkg-config
    pkgs.openssl
    pkgs.wasm-pack
    pkgs.wasm-bindgen-cli
  ];

  buildInputs = with pkgs; [
    openssl
    openssl.dev
    pkg-config
    zlib.dev
  ];
  LD_LIBRARY_PATH = lib.makeLibraryPath [pkgs.openssl];

  meta = {
    description = "markdown to anki flashcard";
    homepage = "https://github.com/shshemi/tabiew";
    license = lib.licenses.mit;
    maintainers = with lib.maintainers; [];
    mainProgram = "marki";
  };
}

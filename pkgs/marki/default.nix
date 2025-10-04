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
  cargoHash = "sha256-STbg3Notr+X31zBQjQt6OVDiMV2F055NxFZV/3hqb10=";
  cargoAuditable = null;

  nativeBuildInputs = [
    pkgs.gcc
    pkgs.pkg-config
    pkgs.openssl
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

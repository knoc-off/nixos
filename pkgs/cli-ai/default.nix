{
  lib,
  pkgs,
  rustPlatform,
}:
rustPlatform.buildRustPackage rec {
  pname = "cli-ai";
  version = "0.8.5";
  src = ./.;
  useFetchCargoVendor = true;
  cargoHash = "sha256-dYGvc5jIlhtyXmft+eNYUkT8wPcb0zZ2OsAG7hLHNZ8=";
  cargoAuditable = null;

  nativeBuildInputs = [
    pkgs.gcc
    pkgs.pkg-config
    pkgs.openssl
  ];

  buildInputs = with pkgs; [openssl openssl.dev pkg-config zlib.dev];
  LD_LIBRARY_PATH = lib.makeLibraryPath [pkgs.openssl];

  meta = {
    description = "A lightweight TUI application to view and query tabular data files, such as CSV, TSV, and parquet";
    homepage = "https://github.com/shshemi/tabiew";
    license = lib.licenses.mit;
    maintainers = with lib.maintainers; [];
    mainProgram = "cli";
  };
}

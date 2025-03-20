{
  lib,
  rustPlatform,
  fetchFromGitHub,
}:

rustPlatform.buildRustPackage rec {
  pname = "tabiew";
  version = "0.8.5";

  src = fetchFromGitHub {
    owner = "shshemi";
    repo = "tabiew";
    rev = "v${version}";
    hash = "sha256-mBGEw3WyjEmDPo9L+CPOtMiVA+2ndQ2pjo7bUBZZO8o=";
  };

  useFetchCargoVendor = true;
  cargoHash = "sha256-tDXTiVuQMSPewD5MwDj3pSna22Jelbi3fINszMi9P20=";
  cargoAuditable = null;

  meta = {
    description = "A lightweight TUI application to view and query tabular data files, such as CSV, TSV, and parquet";
    homepage = "https://github.com/shshemi/tabiew";
    license = lib.licenses.mit;
    maintainers = with lib.maintainers; [ ];
    mainProgram = "tabiew";
  };
}

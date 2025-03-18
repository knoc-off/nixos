{
  lib,
  rustPlatform,
  fetchFromGitHub,
  pkg-config,
  openssl,
  rust-jemalloc-sys,
  sqlite,
  zstd,
  stdenv,
  darwin,
}:

rustPlatform.buildRustPackage rec {
  pname = "spider";
  version = "2.33.11";

  src = fetchFromGitHub {
    owner = "spider-rs";
    repo = "spider";
    rev = "v${version}";
    hash = "sha256-wrtkBqq1wJWg+0K4+PILPdMQe1AFOhJ1dJHvwq2irQo=";
  };

  doCheck = false;
  cargoHash = "sha256-7niW32dXWEWQKzwzhiwcJ5mosE/V517s4aseSdBxGVE=";

  nativeBuildInputs = [
    pkg-config
    rustPlatform.bindgenHook
  ];

  buildInputs = [
    openssl
    rust-jemalloc-sys
    sqlite
    zstd
  ] ++ lib.optionals stdenv.isDarwin [
    darwin.apple_sdk.frameworks.CoreFoundation
    darwin.apple_sdk.frameworks.IOKit
    darwin.apple_sdk.frameworks.Security
    darwin.apple_sdk.frameworks.SystemConfiguration
  ];

  env = {
    OPENSSL_NO_VENDOR = true;
    ZSTD_SYS_USE_PKG_CONFIG = true;
  };

  meta = {
    description = "A web crawler and scraper for Rust";
    homepage = "https://github.com/spider-rs/spider/tree/main";
    changelog = "https://github.com/spider-rs/spider/blob/${src.rev}/CHANGELOG.md";
    license = lib.licenses.mit;
    maintainers = with lib.maintainers; [ ];
    mainProgram = "spider";
  };
}


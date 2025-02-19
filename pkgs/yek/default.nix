{
  lib,
  rustPlatform,
  fetchFromGitHub,
  pkg-config,
  libgit2,
  openssl,
  zlib,
  stdenv,
  darwin,
}:

rustPlatform.buildRustPackage rec {
  pname = "yek";
  version = "0.18.0";

  src = fetchFromGitHub {
    owner = "bodo-run";
    repo = "yek";
    rev = "v${version}";
    hash = "sha256-SUtQX01O3XEjTkdPNGHobbVDYxTGVNhCl2fccfFwtug=";
  };

  cargoHash = "sha256-jggzEJZBO3aigoWZV7f5FxT9ycnYfownl6r4Uhg4yo0=";

  nativeBuildInputs = [
    pkg-config
  ];

  buildInputs = [
    libgit2
    openssl
    zlib
  ] ++ lib.optionals stdenv.isDarwin [
    darwin.apple_sdk.frameworks.Security
  ];

  env = {
    OPENSSL_NO_VENDOR = true;
  };

  meta = {
    description = "A fast Rust based tool to serialize text-based files in a repository or directory for LLM consumption";
    homepage = "git@github.com:bodo-run/yek.git";
    changelog = "https://github.com/bodo-run/yek/blob/${src.rev}/CHANGELOG.md";
    license = lib.licenses.mit;
    maintainers = with lib.maintainers; [ ];
    mainProgram = "yek";
  };
}

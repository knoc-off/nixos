{
  pkgs,
  rustPlatform,
  lib,
}:
rustPlatform.buildRustPackage rec {
  pname = "actix-backend";
  version = "0.1.0";
  src = ./.;
  cargoLock.lockFile = ./Cargo.lock;

  nativeBuildInputs = with pkgs; [
    (rust-bin.stable."1.76.0".default.override {
      extensions = ["rust-src"];
    })
    pkg-config
    binaryen
  ];

  buildInputs =
    [
      pkgs.openssl.dev
      pkgs.pkg-config
      pkgs.zlib.dev
      pkgs.sqlite
    ]
    ++ lib.optionals pkgs.stdenv.isDarwin (with pkgs.darwin.apple_sdk.frameworks; [
      libiconv
      CoreServices
      SystemConfiguration
    ]);
}

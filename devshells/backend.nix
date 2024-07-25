{
  pkgs,
  rust-overlay,
}: let
  rustPkgs = pkgs.extend (import rust-overlay);
in
  pkgs.mkShell {
    commonBuildInputs = with rustPkgs;
      [
        openssl.dev
        pkg-config
        zlib.dev
      ]
      ++ lib.optionals stdenv.isDarwin (with darwin.apple_sdk.frameworks; [
        libiconv
        CoreServices
        SystemConfiguration
      ]);

    nativeBuildInputs = with rustPkgs; [
      cargo-edit
      cargo-generate
      (rust-bin.stable."1.76.0".default.override {
        extensions = ["rust-src"];
      })
      rust-analyzer
      sccache
      pkg-config
    ];

    RUST_BACKTRACE = 1;
  }

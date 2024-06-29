{ pkgs, rustPlatform, lib, rust-overlay }:
let
  rustPkgs = pkgs.extend (import rust-overlay);
in
rustPlatform.buildRustPackage rec {
  pname = "portfolio";
  version = "0.1.0";
  src = ./.;
  cargoLock.lockFile = ./Cargo.lock;

  nativeBuildInputs = with rustPkgs; [
    (rust-bin.stable."1.76.0".default.override {
      extensions = [ "rust-src" ];
      targets = [ "wasm32-unknown-unknown" ];
    })
    pkg-config
    trunk
    binaryen
    dart-sass
    tailwindcss
    wasm-bindgen-cli
  ];

  buildInputs = [
    pkgs.super-tiny-icons

    pkgs.openssl.dev
    pkgs.pkg-config
    pkgs.zlib.dev
  ] ++ lib.optionals pkgs.stdenv.isDarwin (with pkgs.darwin.apple_sdk.frameworks; [
    libiconv
    CoreServices
    SystemConfiguration
  ]);


  buildPhase = ''
    runHook preBuild
    mkdir -p $TMPDIR/output

    ln -s ${pkgs.super-tiny-icons}/ icons
    ln -s ${pkgs.font-awesome}/share/fonts/opentype/ font-awesome

    trunk build --release --offline --dist $TMPDIR/output --public-url /
    runHook postBuild
  '';

  #installPhase = ''
  #  runHook preInstall
  #  mkdir -p $out/lib
  #  cp -r $TMPDIR/output/* $out/lib/
  #  runHook postInstall
  #'';
}

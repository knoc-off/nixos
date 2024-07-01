{ pkgs, rustPlatform, lib }:
rustPlatform.buildRustPackage rec {
  pname = "portfolio";
  version = "0.1.0";
  src = ./.;
  cargoLock.lockFile = ./Cargo.lock;

  nativeBuildInputs = with pkgs; [
    (rust-bin.stable."1.76.0".default.override {
      extensions = [ "rust-src" ];
      targets = [ "wasm32-unknown-unknown" ];
    })
    pkg-config
    trunk

    #(trunk.overrideAttrs (old: {
    #  version = "0.16.0";
    #}))

    binaryen

    dart-sass

    #(dart-sass.overrideAttrs (old: {
    #  version = "1.69.5";
    #}))

    tailwindcss

    wasm-bindgen-cli
  ];

  buildInputs = [
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

    TRUNK_SKIP_VERSION_CHECK=true trunk build --release --offline --dist $TMPDIR/output --public-url /
    #trunk build --release --offline --public-url /
    #RUST_BACKTRACE=full trunk build --release --offline --public-url /
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out/lib
    cp -r $TMPDIR/output/* $out/lib/
    runHook postInstall
  '';
}

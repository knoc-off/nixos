{
  pkgs,
  rustPlatform,
  lib,
}:
rustPlatform.buildRustPackage rec {
  pname = "portfolio";
  version = "0.1.0";
  src = ./.;
  cargoLock.lockFile = ./Cargo.lock;

  nativeBuildInputs = with pkgs; [
    (rust-bin.stable."1.76.0".default.override {
      extensions = ["rust-src"];
      targets = ["wasm32-unknown-unknown"];
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

  buildInputs =
    [
      pkgs.openssl.dev
      pkgs.pkg-config
      pkgs.zlib.dev
    ]
    ++ lib.optionals pkgs.stdenv.isDarwin (with pkgs.darwin.apple_sdk.frameworks; [
      libiconv
      CoreServices
      SystemConfiguration
    ]);



  buildPhase = ''
    runHook preBuild
    mkdir -p $TMPDIR/output

    # There should be a better way to do this.
    mkdir static/icons/flags -p
    cp -r ${pkgs.circle-flags}/share/circle-flags-svg/* static/icons/flags
    mkdir static/fonts/material -p
    cp -r ${pkgs.material-icons}/share/fonts/opentype/* static/fonts/material
    mkdir static/icons/tiny -p
    cp -r ${pkgs.super-tiny-icons}/share/icons/SuperTinyIcons/svg/* static/icons/tiny

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


  shellHook = ''
    clear
    ${pkgs.gum}/bin/gum confirm "create new symbolic links?"

    if [ $? = 0 ]; then
      mkdir -p static/icons/flags
      mkdir -p static/fonts/material
      mkdir -p static/icons/tiny

      cp -rf ${pkgs.circle-flags}/share/circle-flags-svg/* static/icons/flags/
      cp -rf ${pkgs.material-icons}/share/fonts/opentype/* static/fonts/material/
      cp -rf ${pkgs.super-tiny-icons}/share/icons/SuperTinyIcons/svg/* static/icons/tiny/

      chmod -R a+rw static/icons/flags
      chmod -R a+rw static/fonts/material
      chmod -R a+rw static/icons/tiny
    fi
  '';
}

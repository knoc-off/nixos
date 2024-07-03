{ pkgs, rust-overlay }:
let
  rustPkgs = pkgs.extend (import rust-overlay);
in
pkgs.mkShell {
  commonBuildInputs = with rustPkgs;  [
    openssl.dev
    pkg-config
    zlib.dev
  ] ++ lib.optionals stdenv.isDarwin (with darwin.apple_sdk.frameworks; [
    libiconv
    CoreServices
    SystemConfiguration
  ]);

  nativeBuildInputs = with rustPkgs; [
    cargo-edit
    cargo-generate
    (rust-bin.stable."1.76.0".default.override {
      extensions = [ "rust-src" ];
      targets = [ "wasm32-unknown-unknown" ];
    })
    rust-analyzer
    sccache
    pkg-config
    trunk
    tailwindcss
    binaryen
    dart-sass
    wasm-bindgen-cli
  ];

  env = {
    TRUNK_SKIP_VERSION_CHECK = "true";
  };

  shellHook = ''
      #cd nix/pkgs/portfolio
      clear
      echo "create new symbolic links? (y/n)"
      read confirmation

      if [ "$confirmation" = "y" ]; then

        mkdir static/icons/flags -p
        cp -r ${pkgs.circle-flags}/share/circle-flags-svg/* static/icons/flags
        mkdir static/fonts/material -p
        cp -r ${pkgs.material-icons}/share/fonts/opentype/* static/fonts/material
        mkdir static/icons/tiny -p
        cp -r ${pkgs.super-tiny-icons}/share/icons/SuperTinyIcons/svg/* static/icons/tiny

      fi
    '';
  RUST_BACKTRACE = 1;
}


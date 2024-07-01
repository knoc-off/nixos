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
      echo "remove 'icons' and create new symbolic links? proceed? (y/n)"
      read confirmation

      if [ "$confirmation" = "y" ]; then
          #cd nix/pkgs/portfolio
          rm icons
          ln -s ${pkgs.super-tiny-icons}/ icons
          ln -s ${pkgs.font-awesome}/share/fonts/opentype/ font-awesome
      fi
    '';
  RUST_BACKTRACE = 1;
}


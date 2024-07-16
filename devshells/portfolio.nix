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
        targets = ["wasm32-unknown-unknown"];
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

    RUST_BACKTRACE = 1;
  }

{ pkgs, rustPlatform, lib }:

let
  # Node.js and npm for building Tailwind CSS
  nodejs = pkgs.nodejs; # Node.js package
in
rustPlatform.buildRustPackage rec {
  pname = "axum";
  version = "0.1.0";
  src = ./.;
  cargoLock.lockFile = ./Cargo.lock;

  nativeBuildInputs = with pkgs; [
    (rust-bin.stable."1.82.0".default.override {
      extensions = ["rust-src"];
      targets = ["wasm32-unknown-unknown"];
    })
    pkg-config
    nodejs
  ];

  buildInputs =
    [
      # Node.js dependencies
      pkgs.nodePackages.tailwindcss
      pkgs.nodePackages.postcss
      pkgs.nodePackages.autoprefixer

      pkgs.openssl.dev
      pkgs.pkg-config
      pkgs.zlib.dev
    ];

  # Build Tailwind CSS before compiling the Rust project
  preBuild = ''
    # Navigate to the directory containing the CSS files
    cd ${src}/static/css

    # Generate Tailwind CSS build locally
    ${pkgs.nodePackages.tailwindcss}/bin/tailwindcss \
      -i ./styles.css \
      -o ./output.css \
      --minify
  '';

  buildPhase = ''
    # Build the Rust project
    cargo build --release
  '';

  installPhase = ''
    # Install the Rust binary
    mkdir -p $out/bin
    cp target/release/axum $out/bin/

    # Install the static files, including the built CSS
    mkdir -p $out/static/css
    cp -r ${src}/static/* $out/static/

    # Optionally, if you have templates or other assets
    mkdir -p $out/templates
    cp -r ${src}/templates/* $out/templates/
  '';

  # Set any necessary environment variables (if needed)
  meta = with lib; {
    description = "An Axum web application with Tailwind CSS integrated via Nix build";
    homepage = "https://example.com";
    license = licenses.mit;
    maintainers = with maintainers; [ yourName ];
  };
}


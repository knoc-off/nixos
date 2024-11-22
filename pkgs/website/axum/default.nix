{ pkgs, rustPlatform, lib }:
let
  # script to build the css

  cssBuildScript = pkgs.writeScriptBin "tailwind-build" ''
    # Use Tailwind CSS standalone CLI to build the CSS
    ${pkgs.tailwindcss}/bin/tailwindcss \
      -i ./tailwind/styles.css \
      -o ./static/css/styles.css \
      -c ./tailwind/tailwind.config.js \
      --minify
  '';

in rustPlatform.buildRustPackage rec {
  pname = "axum-website";
  version = "0.1.0";
  src = ./.;
  cargoLock.lockFile = ./Cargo.lock;

  nativeBuildInputs = with pkgs; [
    (rust-bin.stable."1.82.0".default.override {
      extensions = [ "rust-src" ];
      targets = [ "wasm32-unknown-unknown" ];
    })
    pkg-config
    cssBuildScript
    tailwindcss
  ];

  buildInputs = [ pkgs.openssl.dev pkgs.pkg-config pkgs.zlib.dev ];

  # Build Tailwind CSS before compiling the Rust project
  preBuild = ''
    ${cssBuildScript}/bin/tailwind-build
  '';

  #postBuild = ''
  #  mkdir -p $out
  #  cp -r static $out
  #  cp -r templates $out
  #'';

  # Set any necessary environment variables (if needed)
  meta = with lib; {
    description =
      "An Axum web application with Tailwind CSS integrated via Nix build";
    homepage = "https://example.com";
    license = licenses.mit;
    maintainers = with maintainers; [ yourName ];
  };
}

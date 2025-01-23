{ pkgs, rustPlatform, lib, ... }:
let


  htmxJs = pkgs.fetchurl {
    url = "https://unpkg.com/htmx.org@1.9.2/dist/htmx.min.js";
    hash = "sha256-/TRunIY51GJIk/xFXyQHoJtBgwFzbdGOu7B3ZGN/tHg=";
  };


  fonts = [
    {
      name = "MaterialIconsRound";
      package = pkgs.material-icons;
      file =
        "${pkgs.material-icons}/share/fonts/opentype/MaterialIconsRound-Regular.otf";
      format = "opentype";
      base_class = "mi-round";
      prefix = "MIRound_";
    }
    {
      name = "MaterialSymbolsRounded";
      package = pkgs.material-symbols;
      file =
        "${pkgs.material-symbols}/share/fonts/TTF/MaterialSymbolsRounded.ttf";
      format = "opentype";
      base_class = "ms-round";
      prefix = "MS_";
    }
  ];

  templatePatterns = [ "./templates/*.html" "./templates/**/*.html" ];

  iconProcessor = import ./icon-processor.nix {
    inherit pkgs fonts templatePatterns;
    isDevelopment = false;
    projectRoot = ./.;
  };

  # Development mode processor - includes all icons
  iconProcessorDev = import ./icon-processor.nix {
    inherit pkgs fonts templatePatterns;
    isDevelopment = true;
    projectRoot = ./.;
  };

  # Tailwind build script
  cssBuildScript = pkgs.writeScriptBin "tailwind-build" ''
    ${pkgs.tailwindcss}/bin/tailwindcss \
      -i ./styles.css \
      -o ./static/css/styles.css \
      -c ./tailwind.config.js \
      --minify
  '';

  switchToProdScript = pkgs.writeScriptBin "switch-to-prod" ''
    echo "Switching to production (pruned) assets..."

    # Clean generated directories
    rm -rf ./static/fonts ./static/icons ./static/css ./data ./debug
    mkdir -p ./static/fonts ./static/icons ./static/css ./data ./debug

    # Link static content
    ln -sf ${pkgs.circle-flags}/share/circle-flags-svg/ ./static/icons/circle-flags-svg
    ln -sf ${pkgs.super-tiny-icons}/share/icons/SuperTinyIcons/svg/ ./static/icons/super-tiny-icons

    # Copy production-optimized assets with write permissions
    cp -r ${iconProcessor}/share/fonts/* ./static/fonts/
    chmod -R u+w ./static/fonts

    cp -r ${iconProcessor}/share/data/* ./data/
    chmod -R u+w ./data

    cp -r ${iconProcessor}/share/css/* ./static/css/
    chmod -R u+w ./static/css

    cp -r ${iconProcessor}/debug/* ./debug/
    chmod -R u+w ./debug

    # Rebuild CSS
    ${cssBuildScript}/bin/tailwind-build

    echo "Switched to production assets. Debug information available in ./debug/"
  '';

  switchToDevScript = pkgs.writeScriptBin "switch-to-dev" ''
    echo "Switching to development assets..."

    # Clean and recreate directories
    rm -rf ./static/fonts ./static/icons ./static/css ./data ./debug
    mkdir -p ./static/fonts ./static/icons ./static/css ./data ./debug

    # Link static content
    ln -sf ${pkgs.circle-flags}/share/circle-flags-svg/ ./static/icons/circle-flags-svg
    ln -sf ${pkgs.super-tiny-icons}/share/icons/SuperTinyIcons/svg/ ./static/icons/super-tiny-icons

    # Copy development assets with write permissions
    cp -r ${iconProcessorDev}/share/fonts/* ./static/fonts/
    chmod -R u+w ./static/fonts

    cp -r ${iconProcessorDev}/share/data/* ./data/
    chmod -R u+w ./data

    cp -r ${iconProcessorDev}/share/css/* ./static/css/
    chmod -R u+w ./static/css

    cp -r ${iconProcessorDev}/debug/* ./debug/
    chmod -R u+w ./debug

    # Rebuild CSS
    ${cssBuildScript}/bin/tailwind-build

    echo "Switched to development assets. Debug information available in ./debug/"
  '';

  devSetupScript = pkgs.writeScriptBin "setup-dev-env" ''
    # Clean and create directories
    rm -rf ./static/fonts ./static/icons ./data
    mkdir -p ./static/fonts ./static/icons ./static/css ./static/js ./data

    # Link static content
    ln -sf ${pkgs.circle-flags}/share/circle-flags-svg/ ./static/icons/circle-flags-svg
    ln -sf ${pkgs.super-tiny-icons}/share/icons/SuperTinyIcons/svg/ ./static/icons/super-tiny-icons

    # Link development icon assets
    cp -r ${iconProcessorDev}/share/fonts/* ./static/fonts/
    cp -r ${iconProcessorDev}/share/data/* ./data/
    cp -r ${iconProcessorDev}/share/css/* ./static/css/

    # Copy htmx
    cp ${htmxJs} ./static/js/htmx.min.js

    # Build CSS
    ${cssBuildScript}/bin/tailwind-build
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
    tailwindcss
    python3

    switchToProdScript
    switchToDevScript
  ];

  buildInputs = with pkgs; [ openssl.dev pkg-config zlib.dev ];

  preBuild = ''
    # Create required directories
    mkdir -p ./static/fonts ./static/css ./data ./static/js


    # Copy htmx
    cp ${htmxJs} ./static/js/htmx.min.js

    # Copy production-optimized fonts and data
    cp -r ${iconProcessor}/share/fonts/* ./static/fonts/
    cp -r ${iconProcessor}/share/data/* ./data/
    cp -r ${iconProcessor}/share/css/* ./static/css/

    # Build CSS
    ${cssBuildScript}/bin/tailwind-build
  '';

  shellHook = ''
    ${devSetupScript}/bin/setup-dev-env
  '';

  meta = with lib; {
    description =
      "An Axum web application with Tailwind CSS integrated via Nix build";
    homepage = "https://example.com";
    license = licenses.mit;
    maintainers = with maintainers; [ knoff ];
  };
}

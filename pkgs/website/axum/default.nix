{ pkgs, rustPlatform, lib, tabler-icons, ... }:
let
  htmxJs = pkgs.fetchurl {
    url = "https://unpkg.com/htmx.org@1.9.2/dist/htmx.min.js";
    hash = "sha256-/TRunIY51GJIk/xFXyQHoJtBgwFzbdGOu7B3ZGN/tHg=";
  };

  icons = [
    {
      name = "circle-flags";
      package = pkgs.circle-flags;
      path = "/share/circle-flags-svg";
      prefix = "cf_";
    }
    {
      name = "super-tiny-icons";
      package = pkgs.super-tiny-icons;
      path = "/share/icons/SuperTinyIcons/svg";
      prefix = "sti_";
    }
    {
      name = "tabler-icons-outline";
      package = tabler-icons;
      path = "/share/icons/outline";
      prefix = "tio_";
    }
    {
      name = "tabler-icons-filled";
      package = tabler-icons;
      path = "/share/icons/filled";
      prefix = "tif_";
    }
  ];

  fonts = [
    {
      name = "MaterialIconsRound";
      package = pkgs.material-icons;
      file = "${pkgs.material-icons}/share/fonts/opentype/MaterialIconsRound-Regular.otf";
      format = "opentype";
      base_class = "mi-round";
      prefix = "MIRound_";
    }
    {
      name = "MaterialSymbolsRounded";
      package = pkgs.material-symbols;
      file = "${pkgs.material-symbols}/share/fonts/TTF/MaterialSymbolsRounded.ttf";
      format = "opentype";
      base_class = "ms-round";
      prefix = "MS_";
    }
    {
      name = "FontAwesome";
      package = pkgs.font-awesome;
      file = "${pkgs.font-awesome}/share/fonts/opentype/Font Awesome 6 Free-Solid-900.otf";
      format = "opentype";
      base_class = "fa-solid";
      prefix = "fa_";
    }
  ];

  templatePatterns = [ "./templates/*.html" "./templates/**/*.html" ];


  fontProcessor = dev:
    (import ./font-processor.nix {
      inherit pkgs fonts templatePatterns;
      isDevelopment = dev;
      projectRoot = ./.;
    });


  iconProcessor = dev:
    (import ./icon-processor.nix {
      inherit pkgs icons templatePatterns;
      isDevelopment = dev;
      projectRoot = ./.;
    });


  cssBuildScript = pkgs.writeScriptBin "tailwind-build" ''
    ${pkgs.tailwindcss}/bin/tailwindcss \
      -i ./styles.css \
      -o ./static/css/styles.css \
      -c ./tailwind.config.js \
      --minify
  '';

  # Common operations
  mkDirs = ''
    rm -rf ./static/fonts ./static/icons ./static/css ./data ./debug
    mkdir -p ./static/fonts ./static/icons ./static/css ./data ./debug
  '';

  linkStaticContent = let
    # Function to create a symbolic link command for a single icon set
    mkIconLink = icon: ''
      ln -sf ${icon.package}${icon.path}/ ./static/icons/${icon.name}
    '';
    # Map over the icons list and join the commands with newlines
    linkCommands = builtins.concatStringsSep "\n" (map mkIconLink icons);
  in ''
    # Ensure the icons directory exists
    mkdir -p ./static/icons
    # Create all icon links
    ${linkCommands}
  '';

  copyAssets = isDev: ''
    cp -r ${fontProcessor isDev}/share/fonts/* ./static/fonts/
    cp -r ${fontProcessor isDev}/share/data/* ./data/
    cp -r ${fontProcessor isDev}/share/css/* ./static/css/
    cp -r ${iconProcessor isDev}/share/css/* ./static/css/
    cp -r ${fontProcessor isDev}/debug/* ./debug/
    cp -r ${iconProcessor isDev}/debug/* ./debug/
    chmod -R u+w ./static/fonts ./data ./static/css ./debug
  '';

  mkEnvScript = name: isDev: message: pkgs.writeScriptBin name ''
    echo "${message}"
    ${mkDirs}
    ${linkStaticContent}
    ${copyAssets isDev}
    ${cssBuildScript}/bin/tailwind-build
    echo "Assets switched. Debug information available in ./debug/"
  '';

  switchToProdScript = mkEnvScript "switch-to-prod" false "Switching to production (pruned) assets...";
  switchToDevScript = mkEnvScript "switch-to-dev" true "Switching to development assets...";

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
    cssBuildScript
  ];

  buildInputs = with pkgs; [ openssl.dev pkg-config zlib.dev ];

  preBuild = ''
    mkdir -p ./static/fonts ./static/css ./data ./static/js
    cp ${htmxJs} ./static/js/htmx.min.js
    ${copyAssets false}
    ${cssBuildScript}/bin/tailwind-build
  '';

  shellHook = ''
    ${mkDirs}
    ${linkStaticContent}
    ${copyAssets true}
    cp ${htmxJs} ./static/js/htmx.min.js
    ${cssBuildScript}/bin/tailwind-build
  '';

  meta = with lib; {
    description = "An Axum web application with Tailwind CSS integrated via Nix build";
    homepage = "https://example.com";
    license = licenses.mit;
    maintainers = with maintainers; [ knoff ];
  };
}

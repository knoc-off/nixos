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
    {
      name = "FontAwesome";
      package = pkgs.font-awesome;
      file =
        "${pkgs.font-awesome}/share/fonts/opentype/Font Awesome 6 Free-Solid-900.otf";
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

  dbSetupScript = pkgs.writeScriptBin "setup-database" ''
    DB_PATH="/var/lib/axum-website/db.sqlite"
    DB_DIR="/var/lib/axum-website"

    if [ ! -d "$DB_DIR" ]; then
      echo "Database-Dir doesn't exist: " $DB_DIR
      exit 1
    fi

    if [ ! -f "$DB_PATH" ]; then
      echo "Initializing database..."
      ${pkgs.sqlite}/bin/sqlite3 "$DB_PATH" ".databases"
      echo "Running migrations..."
      ${pkgs.sqlx-cli}/bin/sqlx migrate run --database-url "sqlite:$DB_PATH"
    else
      echo "Database already exists at $DB_PATH"
    fi
  '';

  cssBuildScript = pkgs.writeScriptBin "tailwind-build" ''
    ${pkgs.tailwindcss}/bin/tailwindcss \
      -i ./styles.css \
      -o ./static/css/styles.css \
      -c ./tailwind.config.js \
      --minify
  '';

  # Common operations
  mkDirs = ''
    rm -rf ./static/fonts ./static/icons ./static/css
    mkdir -p ./static/fonts ./static/icons ./static/css
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
    cp -r ${fontProcessor isDev}/share/css/* ./static/css/
    chmod -R u+w ./static/fonts ./static/css
  '';

  mkEnvScript = name: isDev: message:
    pkgs.writeScriptBin name ''
      echo "${message}"
      ${mkDirs}
      ${linkStaticContent}
      ${copyAssets isDev}
      ${cssBuildScript}/bin/tailwind-build
    '';

  switchToProdScript = mkEnvScript "switch-to-prod" false
    "Switching to production (pruned) assets...";
  switchToDevScript =
    mkEnvScript "switch-to-dev" true "Switching to development assets...";

in rustPlatform.buildRustPackage rec {
  pname = "axum-website";
  version = "0.1.0";
  src = ./.;
  cargoLock.lockFile = ./Cargo.lock;

  nativeBuildInputs = with pkgs; [
    # (rust-bin.stable."1.82.0".default.override {
    #   extensions = [ "rust-src" ];
    #   targets = [ "wasm32-unknown-unknown" ];
    # })
    libyaml
    pkg-config
    tailwindcss
    python3
    switchToProdScript
    switchToDevScript
    cssBuildScript
    dbSetupScript
    openssl
    makeWrapper
  ];

  buildInputs = with pkgs; [ openssl openssl.dev pkg-config zlib.dev ];

  preBuild = ''
    mkdir -p ./static/fonts ./static/css ./static/js
    cp ${htmxJs} ./static/js/htmx.min.js
    ${linkStaticContent}
    ${copyAssets false}
    ${cssBuildScript}/bin/tailwind-build

  '';

  # could do the following to make the dev-setup easy, and deployment more automatic.
  # Generate the database:
  # > sqlite3 /opt/website_data/database.db ".databases"
  # Run the sqlx migrations:
  # > cargo sqlx migrate run --database-url sqlite:/opt/website_data/database.db
  shellHook = ''
    ${mkDirs}
    ${linkStaticContent}
    ${copyAssets true}
    if [ ! -f ./static/js/htmx.min.js ]; then
        cp ${htmxJs} ./static/js/htmx.min.js
    fi
    ${cssBuildScript}/bin/tailwind-build
    ${dbSetupScript}/bin/setup-database

    alias reset_db="rm db.sqlite  && cargo sqlx database create && cargo sqlx migrate run"
  '';

  LD_LIBRARY_PATH = lib.makeLibraryPath [ pkgs.openssl ];

  postInstall = ''

    # Create necessary directories
    mkdir -p $out/bin
    mkdir -p $out/share/static/{js,css}

    # Copy the database setup script
    cp ${dbSetupScript}/bin/setup-database $out/bin/



    # Copy static assets
    cp ./static $out/share/ -r
    #cp ${htmxJs} $out/share/static/js/htmx.min.js
    #cp ./static/css/styles.css $out/share/static/css/
    # rm db.sqlite && cargo sqlx database create && cargo sqlx migrate run

    # --- ROBUST WRAPPER SCRIPT ---
    # 1. Move the original, compiled binary to a new name with a "-bin" suffix.
    mv $out/bin/axum-website $out/bin/axum-website-bin

    # 2. Use makeWrapper to create a NEW script at the original location.
    #    This new script sets up the environment and then calls the real binary.
    makeWrapper $out/bin/axum-website-bin $out/bin/axum-website \
      --prefix LD_LIBRARY_PATH : ${lib.makeLibraryPath [ pkgs.openssl ]}
  '';


  meta = with lib; {
    description =
      "An Axum web application with Tailwind CSS integrated via Nix build";
    homepage = "https://example.com";
    license = licenses.mit;
    maintainers = with maintainers; [ knoff ];
  };
}

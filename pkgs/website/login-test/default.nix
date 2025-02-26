{ pkgs, rustPlatform, lib, tabler-icons, ... }:

let
  htmxJs = pkgs.fetchurl {
    url = "https://unpkg.com/htmx.org@1.9.2/dist/htmx.min.js";
    hash = "sha256-/TRunIY51GJIk/xFXyQHoJtBgwFzbdGOu7B3ZGN/tHg=";
  };

  icons = [
    { name = "circle-flags"; package = pkgs.circle-flags; path = "/share/circle-flags-svg"; }
    { name = "super-tiny-icons"; package = pkgs.super-tiny-icons; path = "/share/icons/SuperTinyIcons/svg"; }
    { name = "tabler-icons-outline"; package = tabler-icons; path = "/share/icons/outline"; }
    { name = "tabler-icons-filled"; package = tabler-icons; path = "/share/icons/filled"; }
  ];

  fonts = [
    { name = "MaterialIconsRound"; file = "${pkgs.material-icons}/share/fonts/opentype/MaterialIconsRound-Regular.otf"; }
    { name = "MaterialSymbolsRounded"; file = "${pkgs.material-symbols}/share/fonts/TTF/MaterialSymbolsRounded.ttf"; }
    { name = "FontAwesome"; file = "${pkgs.font-awesome}/share/fonts/opentype/Font Awesome 6 Free-Solid-900.otf"; }
  ];

  dbSetupScript = pkgs.writeScriptBin "setup-database" ''
    DB_PATH="$1"
    DB_DIR="dirname $1"

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

  setupAssetsScript = pkgs.writeScriptBin "setup-assets" ''
    # Create directories
    rm -rf ./static/fonts ./static/icons ./static/css ./static/js
    mkdir -p ./static/fonts ./static/icons ./static/css ./static/js

    # Link icons
    ${lib.concatMapStringsSep "\n" (icon: ''
      ln -sf ${icon.package}${icon.path}/ ./static/icons/${icon.name}
    '') icons}

    # Copy fonts
    ${lib.concatMapStringsSep "\n" (font: ''
      cp ${font.file} ./static/fonts/
    '') fonts}

    # Copy JS
    cp ${htmxJs} ./static/js/htmx.min.js

    # Build CSS
    ${pkgs.tailwindcss}/bin/tailwindcss \
      -i ./styles.css \
      -o ./static/css/styles.css \
      -c ./tailwind.config.js \
      --minify
  '';

in rustPlatform.buildRustPackage rec {
  pname = "axum-website";
  version = "0.1.0";
  src = ./.;
  cargoLock.lockFile = ./Cargo.lock;

  nativeBuildInputs = with pkgs; [
    (rust-bin.nightly.latest.default.override {
      extensions = [ "rust-src" ];
      targets = [ "wasm32-unknown-unknown" ];
    })
    libyaml
    pkg-config
    tailwindcss
    python3
    setupAssetsScript
    dbSetupScript
    sqlite
  ];

  buildInputs = with pkgs; [ openssl.dev pkg-config zlib.dev ];

  preBuild = ''
    ${setupAssetsScript}/bin/setup-assets
  '';

  shellHook = ''
    ${setupAssetsScript}/bin/setup-assets
    ${dbSetupScript}/bin/setup-database
  '';

  postBuild = ''
    mkdir -p $out/bin $out/share
    cp ${dbSetupScript}/bin/setup-database $out/bin/
    cp -r ./static $out/share/
  '';

  meta = with lib; {
    description = "An Axum web application with Tailwind CSS integrated via Nix build";
    homepage = "https://example.com";
    license = licenses.mit;
    maintainers = with maintainers; [ knoff ];
  };
}


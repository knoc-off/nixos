{
  lib,
  pkgs,
  fenix,
}: let
  rustPlatform = pkgs.makeRustPlatform {
    cargo = fenix.minimal.toolchain;
    rustc = fenix.minimal.toolchain;
  };

  dbPath = "./.fuse-fs.db";
in
  rustPlatform.buildRustPackage {
    pname = "recipt-printer";
    version = "0.1.0";
    src = ./.;

    cargoLock = {
      lockFile = ./Cargo.lock;
    };

    nativeBuildInputs = with pkgs; [
      pkg-config
      makeWrapper
      sqlx-cli
    ];

    buildInputs = with pkgs; [
      systemd # provides libudev
      sqlite
    ];

    # Set DATABASE_URL for compile-time query checking
    DATABASE_URL = "sqlite://${dbPath}";

    # Create database and run migrations before build
    preBuild = ''
      export DATABASE_URL=sqlite://${dbPath}
      # Create database if it doesn't exist
      if [ ! -f ${dbPath} ]; then
        ${pkgs.sqlite}/bin/sqlite3 ${dbPath} "VACUUM;"
      fi
      # Run migrations
      if [ -d migrations ]; then
        ${pkgs.sqlx-cli}/bin/sqlx database create || true
        ${pkgs.sqlx-cli}/bin/sqlx migrate run
      fi
    '';

    # Fix runtime library paths
    postInstall = ''
      wrapProgram $out/bin/recipt-printer \
        --prefix LD_LIBRARY_PATH : "${pkgs.lib.makeLibraryPath [pkgs.systemd]}"
    '';

    # doCheck = false;

    # Shell environment for development
    shellHook = ''
      export DATABASE_URL=sqlite://${dbPath}
      # Create database if it doesn't exist
      if [ ! -f ${dbPath} ]; then
        echo "Creating SQLite database at ${dbPath}..."
        ${pkgs.sqlite}/bin/sqlite3 ${dbPath} "VACUUM;"
      fi
      # Run migrations if they exist
      if [ -d migrations ]; then
        echo "Running migrations..."
        ${pkgs.sqlx-cli}/bin/sqlx database create || true
        ${pkgs.sqlx-cli}/bin/sqlx migrate run || true
      fi
      echo "DATABASE_URL set to: $DATABASE_URL"
    '';

    meta = {
      description = "ESP32-C3 train time display";
      license = lib.licenses.mit;
      maintainers = [];
      platforms = lib.platforms.all;
    };
  }

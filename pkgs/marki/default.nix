{
  lib,
  pkgs,
  ...
}: let
  cargoToml = builtins.fromTOML (builtins.readFile ./Cargo.toml);
  version = cargoToml.workspace.package.version;
in
  pkgs.rustPlatform.buildRustPackage {
    pname = "markid";
    inherit version;

    src = lib.cleanSource ./.;

    cargoLock = {
      lockFile = ./Cargo.lock;
    };

    # Build just the daemon binary; its transitive deps pull the rest of the workspace.
    cargoBuildFlags = ["-p" "markid"];
    cargoTestFlags = ["--workspace"];

    # reqwest with rustls-tls needs no system OpenSSL; keep nativeBuildInputs minimal.
    nativeBuildInputs = [pkgs.pkg-config];

    meta = {
      description = "Daemon that syncs a directory of markdown cards with Anki via AnkiConnect";
      license = lib.licenses.mit;
      mainProgram = "markid";
    };
  }

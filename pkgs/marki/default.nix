{
  lib,
  pkgs,
  ...
}: let
  cargoToml = builtins.fromTOML (builtins.readFile ./Cargo.toml);
  version = cargoToml.workspace.package.version;

  naturalEarthData = pkgs.callPackage ../natural-earth-data {};
  geoBoundariesData = pkgs.callPackage ../geoboundaries-data {};

  markid = pkgs.rustPlatform.buildRustPackage {
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

    # The binary is now `marki` (one-shot-first CLI). Keep `markid` as a
    # back-compat alias so existing systemd units / scripts keep working.
    postInstall = ''
      if [ -e "$out/bin/marki" ] && [ ! -e "$out/bin/markid" ]; then
        ln -s marki "$out/bin/markid"
      fi
    '';

    meta = {
      description = "One-shot CLI (with optional watch daemon) that syncs a repo of markdown cards with Anki via AnkiConnect";
      license = lib.licenses.mit;
      mainProgram = "marki";
    };

    passthru.devShell = pkgs.mkShell {
      inputsFrom = [markid];
      nativeBuildInputs = [
        pkgs.gdal
        pkgs.curl
        pkgs.jq
      ];
      NATURAL_EARTH_DATA = "${naturalEarthData}";
      GEOBOUNDARIES_DATA = "${geoBoundariesData}";
      shellHook = ''
        echo "marki dev shell"
        echo "  NATURAL_EARTH_DATA=$NATURAL_EARTH_DATA"
        echo "  GEOBOUNDARIES_DATA=$GEOBOUNDARIES_DATA"
      '';
    };
  };
in
  markid

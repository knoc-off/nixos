{
  lib,
  pkgs,
  self,
  ...
}:
let
  cargoToml = builtins.fromTOML (builtins.readFile ./Cargo.toml);
  version = cargoToml.workspace.package.version;

  naturalEarthData = self.packages.${pkgs.stdenv.hostPlatform.system}.natural-earth-data;
  geoBoundariesData = self.packages.${pkgs.stdenv.hostPlatform.system}.geoboundaries-data;

  marki = pkgs.rustPlatform.buildRustPackage {
    pname = "marki";
    inherit version;

    src = lib.cleanSource ./.;

    cargoLock = {
      lockFile = ./Cargo.lock;
    };

    # Build just the CLI binary; its transitive deps pull the rest of the workspace.
    cargoBuildFlags = [
      "-p"
      "marki"
    ];
    cargoTestFlags = [ "--workspace" ];

    # reqwest with rustls-tls needs no system OpenSSL; keep nativeBuildInputs minimal.
    nativeBuildInputs = [ pkgs.pkg-config ];

    meta = {
      description = "One-shot CLI (with optional watch daemon) that syncs a repo of markdown cards directly into an Anki collection file";
      license = lib.licenses.mit;
      mainProgram = "marki";
    };

    passthru.devShell = pkgs.mkShell {
      inputsFrom = [ marki ];
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
marki

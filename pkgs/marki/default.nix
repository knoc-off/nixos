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
  # Embedded at compile time (include_bytes!) so PNG previews can draw
  # map labels; the binary needs no fonts at runtime.
  labelFont = "${pkgs.dejavu_fonts}/share/fonts/truetype/DejaVuSans.ttf";

  # Anki's own Python library, which marki runs (crates/marki/src/sync/sync.py)
  # to sync its collection. From the same nixpkgs as anki-sync-server, so the
  # client and server speak the same protocol version. The lib output's
  # site-packages bundles its Python dependencies.
  ankiPython = pkgs.writeShellScript "marki-anki-python" ''
    PYTHONNOUSERSITE=true PYTHONPATH=${pkgs.anki.lib}/${pkgs.python3.sitePackages} \
      exec ${lib.getExe pkgs.python3} "$@"
  '';

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
    nativeBuildInputs = [
      pkgs.pkg-config
      pkgs.makeWrapper
    ];

    MARKI_FONT = labelFont;

    postInstall = ''
      wrapProgram $out/bin/marki --set-default MARKI_PYTHON ${ankiPython}
    '';

    meta = {
      description = "Syncs a repo of markdown cards into Anki, as an Anki sync client";
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
      MARKI_FONT = labelFont;
      MARKI_PYTHON = "${ankiPython}";
      shellHook = ''
        echo "marki dev shell"
        echo "  NATURAL_EARTH_DATA=$NATURAL_EARTH_DATA"
        echo "  GEOBOUNDARIES_DATA=$GEOBOUNDARIES_DATA"
      '';
    };
  };
in
marki

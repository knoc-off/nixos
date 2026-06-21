# geoBoundaries CGAZ vector data — the Comprehensive Global Administrative
# Zones composite (ADM0/1/2), simplified topology-aware at package time and
# split into the per-country `<ISO>_ADM<n>.geojson` layout marki-map reads.
#
# Why CGAZ (not gbOpen per-country): gbOpen digitizes every country
# independently, so a shared border exists as two non-coincident polylines
# -> double lines / slivers when drawn together (continent/neighbours maps).
# CGAZ is clipped to a common international boundary with gaps filled, so
# adjacent units share *identical* border vertices. A single source, one
# border per edge.
#
# Why the python step: ordinary per-feature Douglas-Peucker decimation
# (ogr2ogr -simplify, or the renderer's own simplify) splits those shared
# borders apart again. GEOS *coverage* simplification (shapely.coverage_
# simplify) simplifies each shared edge once, keeping neighbours coincident.
# See ./simplify.py. This runs entirely at build time; the runtime data is
# small per-country GeoJSON.
#
# Two derivations: `cgazRaw` is a fixed-output download (pinned, ~1.3 GB,
# cached once); the outer derivation only re-runs the cheap simplify/split
# when ./simplify.py changes — no re-download.
#
# Data: geoBoundaries CGAZ, CC-BY 4.0. Attribution required.
# Source: https://www.geoboundaries.org/
#
# Consumers read the `GEOBOUNDARIES_DATA` env var, which the markid
# home-manager module sets to this derivation's output.
{
  lib,
  stdenvNoCC,
  curl,
  cacert,
  python3,
}: let
  # Immutable commit the CGAZ files + Open metadata CSV are pinned to.
  metaCommit = "5c25134028196d43ce97b5071934fd0cfc92f09f";
  shortRev = builtins.substring 0 7 metaCommit;

  raw = "https://github.com/wmgeolab/geoBoundaries/raw/${metaCommit}/releaseData";

  # Fixed-output download of the three global CGAZ files (Git-LFS; the
  # github `/raw/` URL 302-redirects to media.githubusercontent.com, which
  # curl -L follows) plus the metadata CSV.
  cgazRaw = stdenvNoCC.mkDerivation {
    pname = "cgaz-raw";
    version = "CGAZ-${shortRev}";

    nativeBuildInputs = [curl cacert];
    dontUnpack = true;
    dontConfigure = true;
    dontBuild = true;

    installPhase = ''
      runHook preInstall
      export SSL_CERT_FILE=${cacert}/etc/ssl/certs/ca-bundle.crt
      mkdir -p "$out"

      for lvl in 0 1 2; do
        echo "fetching CGAZ ADM$lvl ..."
        curl -sSL --retry 5 --retry-delay 2 --fail \
          -o "$out/geoBoundariesCGAZ_ADM$lvl.geojson" \
          "${raw}/CGAZ/geoBoundariesCGAZ_ADM$lvl.geojson"
      done

      # ISO3 -> Continent / UNSDG-subregion mapping for the composites.
      curl -sSL --retry 5 --retry-delay 2 --fail \
        -o "$out/meta.csv" \
        "${raw}/geoBoundariesOpen-meta.csv"

      # Workaround for geoBoundaries issue #4265: India's ADM0 meta row is
      # mislabeled boundaryType=ADM1, which would drop India from the
      # continent/subregion composites the loader builds from ADM0 rows.
      # Only the boundaryType column is wrong (Continent/subregion are
      # correct), so promote it back to ADM0. (CGAZ's geometry already
      # includes India, so no geometry injection is needed here.)
      sed -i -E 's#^("IND-ADM0-[0-9]+","India","IND","[0-9]+"),"ADM1"#\1,"ADM0"#' "$out/meta.csv"

      runHook postInstall
    '';

    outputHashMode = "recursive";
    outputHashAlgo = "sha256";
    outputHash = "sha256-nA2tvqhQt+yK74pbeYvNvLg3sxqojA7Y/oaSQNPUDyk=";
  };

  pyenv = python3.withPackages (ps: [ps.shapely ps.numpy]);
in
  stdenvNoCC.mkDerivation {
    pname = "geoboundaries-data";
    version = "CGAZ-${shortRev}";

    nativeBuildInputs = [pyenv];
    dontUnpack = true;
    dontConfigure = true;

    buildPhase = ''
      runHook preBuild
      mkdir -p "$out"
      SRC=${cgazRaw} out="$out" python3 ${./simplify.py}
      echo "geoboundaries: wrote $(ls "$out"/*.geojson | wc -l) per-country files"
      runHook postBuild
    '';

    dontInstall = true;

    meta = with lib; {
      description = "geoBoundaries CGAZ ADM0/1/2, coverage-simplified per-country, for marki-map";
      homepage = "https://www.geoboundaries.org/";
      license = licenses.cc-by-40;
      platforms = platforms.all;
    };
  }

# geoBoundaries gbOpen vector data — per-country ADM0/ADM1/ADM2
# administrative boundaries (simplified geometry) + the open metadata
# CSV. Bundled here so `marki-map` can resolve `country/<iso>`,
# `adm1|adm2|adm3/<iso>/<name>`, `continent/<name>`, `subregion/<name>`
# and `neighbors/<iso>` references at runtime without touching the
# network.
#
# Data: geoBoundaries Open (gbOpen), CC-BY 4.0. Attribution required.
# Source: https://www.geoboundaries.org/
#
# Reproducibility: the metadata CSV is fetched from one pinned commit
# (`metaCommit`). Every per-country download link inside that CSV is
# itself pinned to an immutable data commit, so we derive each
# `_simplified.geojson` URL straight from the CSV's `staticDownloadLink`
# column (swapping the `-all.zip` suffix). The full output is therefore
# determined by `metaCommit` alone — a single fixed-output hash covers
# it. Bump `metaCommit` + `outputHash` together to refresh the dataset.
#
# Consumers read the `GEOBOUNDARIES_DATA` env var, which the markid
# home-manager module sets to this derivation's output.
{
  lib,
  stdenvNoCC,
  curl,
  cacert,
}:
let
  # Immutable commit to fetch the Open metadata CSV from. Its
  # per-country download links pin the actual boundary data to their own
  # (possibly older) immutable commit; we follow whatever they point at.
  metaCommit = "5c25134028196d43ce97b5071934fd0cfc92f09f";
  # Administrative levels to bundle. The renderer supports adm1/adm2/adm3;
  # add `3` here to also pull ADM3 (much larger; fewer countries provide
  # it).
  levels = "0 1 2";
in
stdenvNoCC.mkDerivation {
  pname = "geoboundaries-data";
  version = "gbOpen-${builtins.substring 0 7 metaCommit}";

  nativeBuildInputs = [curl cacert];

  # No inputs; everything is fetched at build time from pinned URLs.
  dontUnpack = true;
  dontConfigure = true;
  dontBuild = true;
  dontPatch = true;

  installPhase = ''
    runHook preInstall
    export SSL_CERT_FILE=${cacert}/etc/ssl/certs/ca-bundle.crt

    mkdir -p "$out"

    # 1. Pinned metadata CSV (carries ISO3 -> Continent / UNSDG-subregion
    #    used for the continent/ and subregion/ composites).
    curl -sSL --retry 5 --retry-delay 2 --fail \
      -o "$out/meta.csv" \
      "https://github.com/wmgeolab/geoBoundaries/raw/${metaCommit}/releaseData/geoBoundariesOpen-meta.csv"

    # 2. Extract the commit-pinned per-(ISO, level) download links from
    #    the CSV's staticDownloadLink column, restricted to the desired
    #    levels. Regex filtering avoids fragile positional CSV parsing.
    lvlpat="$(echo "${levels}" | tr ' ' '|')"
    grep -oE "https://github.com/wmgeolab/geoBoundaries/raw/[0-9a-f]+/releaseData/gbOpen/[A-Z]+/ADM($lvlpat)/geoBoundaries-[A-Z]+-ADM($lvlpat)-all\.zip" \
      "$out/meta.csv" | sort -u > urls.txt

    echo "geoboundaries: $(wc -l < urls.txt) boundary files to fetch"

    # 3. Build a tab-separated (url, dest) worklist: each `-all.zip` link
    #    maps to its sibling `_simplified.geojson`, saved as
    #    `<ISO>_ADM<n>.geojson`.
    : > work.txt
    while read -r allzip; do
      iso="$(echo "$allzip" | sed -E 's#.*/gbOpen/([A-Z]+)/ADM[0-9]/.*#\1#')"
      lvl="$(echo "$allzip" | sed -E 's#.*/(ADM[0-9])/.*#\1#')"
      gj="$(echo "$allzip" | sed -E 's#-all\.zip$#_simplified.geojson#')"
      printf '%s\t%s/%s_%s.geojson\n' "$gj" "$out" "$iso" "$lvl" >> work.txt
    done < urls.txt

    # 4. Fetch in parallel.
    xargs -P 8 -d '\n' -a work.txt -I{} sh -c '
      url="$(printf "%s" "{}" | cut -f1)"
      dest="$(printf "%s" "{}" | cut -f2)"
      curl -sSL --retry 5 --retry-delay 2 --fail -o "$dest" "$url"
    '

    echo "geoboundaries: fetched $(ls "$out"/*.geojson | wc -l) geojson files"
    runHook postInstall
  '';

  # Fixed-output: content is fully determined by the pinned metaCommit.
  outputHashMode = "recursive";
  outputHashAlgo = "sha256";
  outputHash = "sha256-1hPTD1U+tD6DoA/9KlBlSqP2r3HXelrmq3FqN8+qFMY=";

  meta = with lib; {
    description = "geoBoundaries gbOpen ADM0/1/2 simplified boundaries + metadata for marki-map";
    homepage = "https://www.geoboundaries.org/";
    license = licenses.cc-by-40;
    platforms = platforms.all;
  };
}

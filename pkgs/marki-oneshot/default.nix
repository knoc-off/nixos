# marki-oneshot — a self-contained shell wrapper that runs a single
# `markid` reconcile cycle with the offline map-data env vars baked in.
#
# `markid push --wait-for-anki` does exactly one iteration of the watch
# loop (scan → reconcile → push) and exits, waiting for AnkiConnect to
# come up first. This wrapper points `NATURAL_EARTH_DATA` and
# `GEOBOUNDARIES_DATA` at their Nix store outputs so `map` blocks resolve
# offline without any per-host configuration. All other arguments
# (`--config`, `--cards-dir`, `--anki-endpoint`, …) pass straight
# through.
#
# The two data env vars are set with `:=` so an explicit override in the
# caller's environment still wins.
#
# Run it with:  nix run .#marki-oneshot -- --config /path/to/config.toml
{
  writeShellApplication,
  callPackage,
}: let
  markid = callPackage ../marki {};
  naturalEarthData = callPackage ../natural-earth-data {};
  geoBoundariesData = callPackage ../geoboundaries-data {};
in
  writeShellApplication {
    name = "marki-oneshot";
    runtimeInputs = [markid];
    text = ''
      : "''${NATURAL_EARTH_DATA:=${naturalEarthData}}"
      : "''${GEOBOUNDARIES_DATA:=${geoBoundariesData}}"
      export NATURAL_EARTH_DATA GEOBOUNDARIES_DATA
      exec markid push --wait-for-anki "$@"
    '';
  }

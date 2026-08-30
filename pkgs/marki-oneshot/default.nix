# marki-oneshot — `marki` with the offline map-data env vars baked in.
#
# This is a thin pass-through wrapper around the `marki` CLI that points
# `NATURAL_EARTH_DATA` and `GEOBOUNDARIES_DATA` at their Nix store
# outputs, so `map` blocks resolve offline without any per-host
# configuration. Every argument is forwarded to `marki`, so all
# subcommands work: `marki-oneshot init`, `marki-oneshot status`,
# `marki-oneshot render-map …`, etc.
#
# With NO arguments it runs `marki push` -- exactly one scan -> reconcile
# -> write cycle against the configured collection file.
#
# The two data env vars are set with `:=` so an explicit override in the
# caller's environment still wins.
#
# Run it with:  nix run .#marki-oneshot -- init
#               nix run .#marki-oneshot -- --config /path/to/config.toml
#               nix run .#marki-oneshot                 # one-shot push
{
  writeShellApplication,
  pkgs,
  self,
}:
let
  system = pkgs.stdenv.hostPlatform.system;
  marki = self.packages.${system}.marki;
  naturalEarthData = self.packages.${system}.natural-earth-data;
  geoBoundariesData = self.packages.${system}.geoboundaries-data;
in
writeShellApplication {
  name = "marki-oneshot";
  runtimeInputs = [ marki ];
  text = ''
    : "''${NATURAL_EARTH_DATA:=${naturalEarthData}}"
    : "''${GEOBOUNDARIES_DATA:=${geoBoundariesData}}"
    export NATURAL_EARTH_DATA GEOBOUNDARIES_DATA
    if [ "$#" -eq 0 ]; then
      # No subcommand → the original one-shot push behaviour.
      exec marki push
    else
      # Otherwise forward everything to marki (init, status, …).
      exec marki "$@"
    fi
  '';
}

{
  pkgs,
  lib ? pkgs.lib,
}:
# `nix flake check` runs the color library against its golden fixture.
# The fixture is static JSON (./golden.json), so this needs no special
# evaluator and no network -- just eval.
let
  results = import ./tests.nix { inherit lib; };
  inherit (results) summary;
in
pkgs.runCommand "color-lib-golden"
  {
    passthru = { inherit (results) summary failures; };
  }
  ''
    ${
      if summary.fail == 0 && summary.error == 0 then
        ''echo "color-lib: ${toString summary.pass}/${toString summary.total} passed (${toString summary.known} known divergences, ${toString summary.unsupported} unsupported)"''
      else
        ''
          echo "color-lib: ${toString summary.fail} failed, ${toString summary.error} errored (of ${toString summary.total})" >&2
          echo "inspect: nix eval --impure --json --expr '(import ./lib/color-lib/tests.nix {}).failures'" >&2
          exit 1
        ''
    }
    touch $out
  ''

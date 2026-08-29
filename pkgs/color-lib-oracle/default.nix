{
  lib,
  rustPlatform,
}:
# Reference implementation for the pure-Nix color library in lib/color-lib/.
#
# Reads a JSON array of test cases on stdin, writes the same array back with an
# "expected" field on each case. Used to regenerate lib/color-lib/golden.json:
#
#   nix run .#color-lib-oracle < cases.json > lib/color-lib/golden.json
#
# Deliberately an ordinary native binary. The previous incarnation of this was a
# WASM module invoked through builtins.wasm, which required Determinate Nix and
# deadlocked nix-eval-jobs under parallel workers. Generating a static fixture
# ahead of time means the test path needs no special evaluator at all.
rustPlatform.buildRustPackage {
  pname = "color-lib-oracle";
  version = "0.1.0";
  src = ./.;

  cargoLock.lockFile = ./Cargo.lock;

  meta = {
    description = "Reference color-math implementation used to generate the color-lib golden fixture";
    mainProgram = "color-lib-oracle";
    license = lib.licenses.mit;
  };
}

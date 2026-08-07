{
  nixos-anywhere,
  inputs,
  stdenv,
}:
# nixos-anywhere prepends its own upstream Nix to PATH, and that binary is what
# evaluates the flake -- `--build-on local` only moves the *build*, not the
# eval. lib/color-lib.nix calls builtins.wasm, which exists solely in
# Determinate Nix, so the stock evaluator fails with "attribute 'wasm' missing"
# before it ever reaches the disko script.
nixos-anywhere.override {
  nix = inputs.determinate.inputs.nix.packages.${stdenv.hostPlatform.system}.nix-cli;
}

{
  lib,
  pkgs,
  inputs,
  fenix,
}:
let
  craneLib = (inputs.crane.mkLib pkgs).overrideToolchain fenix.minimal.toolchain;

  src = craneLib.cleanCargoSource ./.;

  commonArgs = {
    inherit src;
    pname = "mqtt-automations";
    version = "0.1.0-unstable";
    strictDeps = true;
  };

  # Dependencies-only build -- cached until Cargo.lock changes.
  cargoArtifacts = craneLib.buildDepsOnly commonArgs;
in
craneLib.buildPackage (
  commonArgs
  // {
    inherit cargoArtifacts;

    meta = {
      description = "Lightweight MQTT automation binaries for Zigbee2MQTT";
      license = lib.licenses.mit;
    };
  }
)

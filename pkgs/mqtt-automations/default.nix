{
  lib,
  pkgs,
  inputs,
  fenix,
}: let
  toolchain = fenix.combine [
    fenix.minimal.toolchain
  ];

  craneLib = (inputs.crane.mkLib pkgs).overrideToolchain toolchain;

  src = lib.cleanSource ./.;

  commonArgs = {
    inherit src;
    pname = "mqtt-automations";
    version = "0.1.0-unstable";
  };

  # Dependencies-only build -- cached until Cargo.lock changes.
  cargoArtifacts = craneLib.buildDepsOnly commonArgs;
in
  craneLib.buildPackage (commonArgs
    // {
      inherit cargoArtifacts;

      meta = {
        description = "Lightweight MQTT automation binaries for Zigbee2MQTT";
        license = lib.licenses.mit;
      };
    })

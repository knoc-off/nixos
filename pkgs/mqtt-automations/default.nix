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

  src = craneLib.cleanCargoSource ./.;

  commonArgs = {
    inherit src;
    pname = "mqtt-automations";
    version = "0.1.0-unstable";
    strictDeps = true;

    # Only build the timezones we actually use — chrono-tz otherwise codegens
    # the entire IANA database, which dominates compile time under emulation.
    CHRONO_TZ_TIMEZONE_FILTER = "Europe/Berlin|UTC";
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

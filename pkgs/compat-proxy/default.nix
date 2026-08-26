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

  commonArgs = {
    # cleanCargoSource rather than cleanSource: it filters down to what
    # cargo actually reads, so editing the README or default.nix doesn't
    # invalidate cargoArtifacts and trigger a full dependency rebuild.
    src = craneLib.cleanCargoSource ./.;
    pname = "compat-proxy";
    version = "0.1.0-unstable";
  };

  # Dependencies-only build -- cached until Cargo.lock changes.
  cargoArtifacts = craneLib.buildDepsOnly commonArgs;
in
  craneLib.buildPackage (commonArgs
    // {
      inherit cargoArtifacts;

      meta = {
        description = "OAuth shim that lets Anthropic-compatible clients use Claude Code credentials";
        license = lib.licenses.mit;
        mainProgram = "compat-proxy";
      };
    })

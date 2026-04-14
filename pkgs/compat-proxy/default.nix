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
    pname = "compat-proxy";
    version = "0.1.0-unstable";
  };

  # Dependencies-only build -- cached until Cargo.lock changes.
  cargoArtifacts = craneLib.buildDepsOnly commonArgs;
in
  craneLib.buildPackage (commonArgs
    // {
      inherit cargoArtifacts;

      # Include the rules directory in the output
      postInstall = ''
        mkdir -p $out/share/compat-proxy
        cp -r ${./rules} $out/share/compat-proxy/rules
        chmod -R u+w $out/share/compat-proxy/rules
      '';

      meta = {
        description = "Typed API compatibility proxy with TOML-driven request/response translation";
        license = lib.licenses.mit;
        mainProgram = "compat-proxy";
      };
    })

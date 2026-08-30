{
  lib,
  pkgs,
  inputs,
  fenix,
  upkgs,
  # Claude Code version to impersonate by default (UA, billing block,
  # billing fingerprint). Defaults to the version of the claude-code
  # package actually installed, auto-wired by `callPackage` (the flake's
  # overlay exposes `upkgs` on `pkgs`), so every caller -- the
  # home-manager service and the bubblewrap jail alike -- impersonates
  # the real installed CLI without needing to pass this explicitly.
  ccVersion ? upkgs.claude-code.version,
}:
let
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
craneLib.buildPackage (
  commonArgs
  // {
    inherit cargoArtifacts;

    COMPAT_PROXY_CC_VERSION_DEFAULT = ccVersion;

    meta = {
      description = "OAuth shim that lets Anthropic-compatible clients use Claude Code credentials";
      license = lib.licenses.mit;
      mainProgram = "compat-proxy";
    };
  }
)

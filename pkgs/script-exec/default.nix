{
  lib,
  stdenv,
}:

# script-exec: an opencode plugin (no daemon, no binary). The tool runs
# entirely inside the jail -- it shells out to the jail's own `nix` to build
# a python3.withPackages environment against the pinned nixpkgs handed in via
# SCRIPT_EXEC_NIXPKGS_PATH (set by pkgs/opencode-bubblewrap), then runs the
# script from that environment. Saved scripts live in ~/scratch/scripts/ with
# their dependency metadata in an in-file header; see opencode-plugin.js.
stdenv.mkDerivation {
  pname = "script-exec";
  version = "0.1.0";

  dontUnpack = true;

  installPhase = ''
    runHook preInstall
    mkdir -p $out/lib/script-exec/plugin
    cp ${./opencode-plugin.js} $out/lib/script-exec/plugin/index.js
    runHook postInstall
  '';

  meta = {
    description = "OpenCode tool: run Python scripts with Nix-resolved dependencies";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
  };
}

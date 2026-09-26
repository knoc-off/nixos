{
  lib,
  stdenv,
  runCommand,
  nodejs,
}:

# axiom-ledger: an opencode plugin (no daemon, no binary). Two tools --
# axiom_post/axiom_get -- backed by one append-only JSONL file per jail
# start dir under ~/.local/share/opencode/axioms/. See opencode-plugin.js
# for the format and the reasoning (append-only log, content-anchor
# staleness, and file-triggered hints instead of an always-on index).
stdenv.mkDerivation {
  pname = "axiom-ledger";
  version = "0.1.0";

  dontUnpack = true;

  installPhase = ''
    runHook preInstall
    mkdir -p $out/lib/axiom-ledger/plugin
    cp ${./opencode-plugin.js} $out/lib/axiom-ledger/plugin/index.js
    runHook postInstall
  '';

  meta = {
    description = "OpenCode tool: a cited, attributed ledger of durable project facts, shared across sessions and sub-agents";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
  };

  # node:test over the pure logic: index ranking/cap, log folding (post +
  # amend + supersede), corrupt-line tolerance. See ./test.mjs. Collected
  # into `nix flake check` by flake.nix.
  passthru.tests.plugin =
    runCommand "axiom-ledger-check"
      {
        nativeBuildInputs = [ nodejs ];
        src = ./.;
      }
      ''
        cp $src/opencode-plugin.js $src/test.mjs .
        node --test test.mjs
        touch $out
      '';
}

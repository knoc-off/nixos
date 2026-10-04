{
  lib,
  stdenv,
  runCommand,
  nodejs,
  git,
  ast-grep,
  ripgrep,
}:

# jev-review: an opencode plugin (no binary). Two tools: jev_review (Jev
# inspects every changed tree-sitter unit, routing each to library probes)
# and jev_probe (the agent writes/saves/dry-runs probes). Shipped probes live
# in ./probes; user probes in ~/scratch/jev-probes override them by name.
# See opencode-plugin.js.
stdenv.mkDerivation {
  pname = "jev-review";
  version = "0.4.0";

  dontUnpack = true;

  installPhase = ''
    runHook preInstall
    mkdir -p $out/lib/jev-review/plugin
    cp -r ${./probes} $out/lib/jev-review/probes
    substitute ${./opencode-plugin.js} $out/lib/jev-review/plugin/index.js \
      --replace-fail '"@astGrep@".startsWith("@") ? "ast-grep" : "@astGrep@"' '"${lib.getExe ast-grep}"' \
      --replace-fail '"@rg@".startsWith("@") ? "rg" : "@rg@"' '"${lib.getExe ripgrep}"' \
      --replace-fail '"@probesDir@".startsWith("@") ? fileURLToPath(new URL("./probes", import.meta.url)) : "@probesDir@"' "\"$out/lib/jev-review/probes\""
    runHook postInstall
  '';

  meta = {
    description = "OpenCode tools: agent-steered Jev review of changed Rust/TypeScript units, with a probe library";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
  };

  # node:test with Jev mocked: units (real ast-grep over a fixture repo),
  # gates/whitelists, routing, recursion caps, cache, output format.
  passthru.tests.plugin =
    runCommand "jev-review-check"
      {
        nativeBuildInputs = [
          nodejs
          git
          ast-grep
          ripgrep
        ];
        src = ./.;
      }
      ''
        cp -r $src/opencode-plugin.js $src/test.mjs $src/probes .
        HOME=$TMPDIR node --test test.mjs
        touch $out
      '';
}

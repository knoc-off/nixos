{
  lib,
  stdenv,
  runCommand,
  nodejs,
  git,
  ast-grep,
  ripgrep,
}:

# jev-review: an opencode plugin (no binary). Three tools: jev_run (Jev over
# any units a harness produces), jev_review (= the shipped `review` harness:
# changed code in a git diff) and jev_probe (the agent writes/saves/dry-runs
# probes, harnesses and langs). Shipped modules live in ./probes,
# ./harnesses, ./langs; user ones in ~/scratch/jev-probes override them by
# name. Also edit hooks: ~/scratch/jev-probes/hooks/<name>.mjs runs after
# edit/write, <name>.mjs.disabled doesn't; the plugin symlinks ./hooks in
# there (off) at startup; the `/jev` TUI dialog (tui.js, a separate TUI
# plugin listed in tui.json) toggles them by renaming. See opencode-plugin.js.
stdenv.mkDerivation {
  pname = "jev-review";
  version = "0.5.0";

  dontUnpack = true;

  installPhase = ''
    runHook preInstall
    mkdir -p $out/lib/jev-review/plugin
    cp -r ${./probes} $out/lib/jev-review/probes
    cp -r ${./harnesses} $out/lib/jev-review/harnesses
    cp -r ${./langs} $out/lib/jev-review/langs
    cp -r ${./hooks} $out/lib/jev-review/hooks
    substitute ${./opencode-plugin.js} $out/lib/jev-review/plugin/index.js \
      --replace-fail '"@astGrep@".startsWith("@") ? "ast-grep" : "@astGrep@"' '"${lib.getExe ast-grep}"' \
      --replace-fail '"@rg@".startsWith("@") ? "rg" : "@rg@"' '"${lib.getExe ripgrep}"' \
      --replace-fail '"@shareDir@".startsWith("@") ? fileURLToPath(new URL(".", import.meta.url)) : "@shareDir@"' "\"$out/lib/jev-review\""
    cp ${./tui.js} $out/lib/jev-review/plugin/tui.js
    runHook postInstall
  '';

  meta = {
    description = "OpenCode tools: agent-steered Jev passes over harness-defined units (code review of any language, and beyond), with a probe library";
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
        cp -r $src/opencode-plugin.js $src/test.mjs $src/probes $src/harnesses $src/langs $src/hooks .
        HOME=$TMPDIR node --test test.mjs
        touch $out
      '';
}

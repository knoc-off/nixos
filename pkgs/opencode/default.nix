{
  upkgs,
  lib,
}:

# Patches opencode's own prompts to remove every mention of "opencode" /
# "OpenCode" that would otherwise appear in requests sent upstream. The
# compat-proxy (pkgs/compat-proxy) already rewrites headers, billing
# metadata and prepends the real Claude Code identity block, but none of
# that matters if the system prompt opencode built into its own binary
# still says "You are OpenCode" -- the proxy only shapes the envelope, not
# the content the model actually reads. This package makes the content
# match the envelope.
#
# Scope (v${upkgs.opencode.version}): "opencode" shows up in two trees --
# packages/opencode/src (the CLI itself) and packages/core/src (the tool
# implementations it imports). Everywhere else it's noise -- import paths
# (`@opencode-ai/...`), internal service names, env var names, and the
# User-Agent header opencode's own WebFetch/WebSearch tools send when
# fetching third-party URLs on the agent's behalf. None of that reaches
# Anthropic. What does reach Anthropic is: session/agent system prompts,
# tool descriptions (tool/*.txt, tool/shell/*.txt), and command templates
# (rendered into the conversation when a user runs e.g. `/init`) -- those
# are exactly the files patched below. The postPatch assertion re-checks
# all of those classes of file regardless of whether this list currently
# finds a hit in them, so a future opencode bump that adds a mention
# somewhere in that surface fails the build loudly instead of leaking
# silently.
#
# session/system.ts picks anthropic.txt whenever the model ID contains
# "claude" -- the only case this deployment's proxy ever hits, since it
# always talks to a claude-* model upstream. anthropic.txt therefore gets
# a full rewrite (prompts/anthropic.txt, kept close to the real Claude
# Code system prompt); the other provider prompts (default/beast/codex/
# gemini/gpt/kimi/trinity/copilot-gpt-5) are unreachable here but get
# their identity lines patched too, in case a model ID ever slips through
# without "claude" in it.
upkgs.opencode.overrideAttrs (old: {
  postPatch =
    (old.postPatch or "")
    + ''
      cp ${./prompts/anthropic.txt} packages/opencode/src/session/prompt/anthropic.txt

      substituteInPlace packages/opencode/src/session/prompt/default.txt \
        --replace-fail \
          "You are opencode, an interactive CLI tool that helps users with software engineering tasks. Use the instructions below and the tools available to you to assist the user." \
          "You are Claude Code, Anthropic's official CLI for Claude. You are an interactive agent that helps users with software engineering tasks. Use the instructions below and the tools available to you to assist the user." \
        --replace-fail \
          "- /help: Get help with using opencode" \
          "- /help: Get help with using Claude Code" \
        --replace-fail \
          "- To give feedback, users should report the issue at https://github.com/anomalyco/opencode/issues" \
          "- To give feedback, users should report the issue at https://github.com/anthropics/claude-code/issues" \
        --replace-fail \
          "When the user directly asks about opencode (eg 'can opencode do...', 'does opencode have...') or asks in second person (eg 'are you able...', 'can you do...'), first use the WebFetch tool to gather information to answer the question from opencode docs at https://opencode.ai" \
          ""

      substituteInPlace packages/opencode/src/session/prompt/beast.txt \
        --replace-fail \
          "You are opencode, an agent - please keep going until the user’s query is completely resolved, before ending your turn and yielding back to the user." \
          "You are Claude Code, an agent - please keep going until the user's query is completely resolved, before ending your turn and yielding back to the user."

      substituteInPlace packages/opencode/src/session/prompt/codex.txt \
        --replace-fail \
          "You are OpenCode, the best coding agent on the planet." \
          "You are Claude Code, Anthropic's official CLI for Claude."

      substituteInPlace packages/opencode/src/session/prompt/copilot-gpt-5.txt \
        --replace-fail \
          "Your name is opencode" \
          "Your name is Claude"

      substituteInPlace packages/opencode/src/session/prompt/gemini.txt \
        --replace-fail \
          "You are opencode, an interactive CLI agent specializing in software engineering tasks. Your primary goal is to help users safely and efficiently, adhering strictly to the following instructions and utilizing your available tools." \
          "You are Claude Code, an interactive CLI agent specializing in software engineering tasks. Your primary goal is to help users safely and efficiently, adhering strictly to the following instructions and utilizing your available tools."

      substituteInPlace packages/opencode/src/session/prompt/trinity.txt \
        --replace-fail \
          "You are opencode, an interactive CLI tool that helps users with software engineering tasks. Use the instructions below and the tools available to you to assist the user." \
          "You are Claude Code, an interactive CLI tool that helps users with software engineering tasks. Use the instructions below and the tools available to you to assist the user."

      substituteInPlace packages/opencode/src/session/prompt/gpt.txt \
        --replace-fail \
          "You are OpenCode, You and the user share the same workspace and collaborate to achieve the user's goals." \
          "You are Claude Code, you and the user share the same workspace and collaborate to achieve the user's goals."

      substituteInPlace packages/opencode/src/session/prompt/kimi.txt \
        --replace-fail \
          "You are OpenCode, an interactive general AI agent running on a user's computer." \
          "You are Claude Code, an interactive general AI agent running on a user's computer."

      substituteInPlace packages/opencode/src/tool/lsp.txt \
        --replace-fail \
          "For workspaceSymbol, filePath is not sent in the LSP workspace/symbol request. It is used by opencode to select and start the matching LSP server." \
          "For workspaceSymbol, filePath is not sent in the LSP workspace/symbol request. It is used by the agent to select and start the matching LSP server."

      # `opencode.json` is a real, still-used config filename here (see
      # modules/opencode/default.nix) -- it stays. Only the "OpenCode
      # sessions" / "OpenCode config" identity phrasing goes.
      for f in \
        packages/opencode/src/command/template/initialize.txt \
        packages/core/src/plugin/command/initialize.txt \
      ; do
        substituteInPlace "$f" \
          --replace-fail \
            'The goal is a compact instruction file that helps future OpenCode sessions avoid mistakes and ramp up quickly.' \
            'The goal is a compact instruction file that helps future agent sessions avoid mistakes and ramp up quickly.' \
          --replace-fail \
            '- repo-local OpenCode config such as `opencode.json`' \
            '- repo-local agent config such as `opencode.json`'
      done

      # Build-time guardrail: fail loudly rather than silently ship a leak.
      # Covers every file class that ends up verbatim in a request body --
      # system/agent prompts and tool/command descriptions, in both the
      # opencode and core packages -- so a future opencode version that
      # adds a new "opencode" mention anywhere in these trees breaks the
      # build instead of shipping quietly. `opencode.json` is the one
      # allowed literal (a real config filename, not branding).
      leaked=0
      for f in \
        packages/opencode/src/session/prompt/*.txt \
        packages/opencode/src/agent/prompt/*.txt \
        packages/opencode/src/agent/generate.txt \
        packages/opencode/src/tool/*.txt \
        packages/opencode/src/tool/shell/*.txt \
        packages/opencode/src/command/template/*.txt \
        packages/core/src/tool/*.txt \
        packages/core/src/plugin/command/*.txt \
      ; do
        [ -f "$f" ] || continue
        if sed 's/opencode\.json/_/g' "$f" | grep -qi 'opencode'; then
          echo "opencode patch: '$f' still mentions opencode:" >&2
          sed 's/opencode\.json/_/g' "$f" | grep -ni 'opencode' >&2
          leaked=1
        fi
      done
      if [ "$leaked" = 1 ]; then
        echo "opencode patch: refusing to build with an opencode-branded prompt/description in the tree" >&2
        exit 1
      fi
    '';

  passthru = (old.passthru or { }) // {
    unpatched = upkgs.opencode;
  };

  meta = (old.meta or { }) // {
    description = "${old.meta.description} (patched: no opencode-branded prompts leak into requests)";
  };
})

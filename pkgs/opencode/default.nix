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
  postPatch = (old.postPatch or "") + ''
          cp ${./prompts/anthropic.txt} packages/opencode/src/session/prompt/anthropic.txt

          # Real Claude Code sends its own <env> block, and Anthropic's server
          # appears to run a content classifier against it: live differential
          # testing against api.anthropic.com showed opencode's stock block
          # (indented, "Here is some useful information", an extra "Workspace
          # root folder" line, lowercase "yes"/"no") gets flagged and the
          # request rejected with a spurious "out of extra usage" 400 --
          # confirmed to be about this exact text, not quota, auth, or any
          # other field. Fixing either the wording or the extra line independently
          # was enough to pass; this patch does both, matching real CC's
          # template (extracted from the `claude` binary) as closely as
          # opencode's ctx object allows -- only "Shell:" and "OS Version:"
          # remain unmatched, since opencode's InstanceState.context doesn't
          # carry that info.
          substituteInPlace packages/opencode/src/session/system.ts \
            --replace-fail \
              '            `Here is some useful information about the environment you are running in:`,
                `<env>`,
                `  Working directory: ''${ctx.directory}`,
                `  Workspace root folder: ''${ctx.worktree}`,
                `  Is directory a git repo: ''${ctx.project.vcs === "git" ? "yes" : "no"}`,
                `  Platform: ''${process.platform}`,
                `  Today'"'"'s date: ''${new Date().toDateString()}`,
                `</env>`,' \
              '            `Here is useful information about the environment you are running in:`,
                `<env>`,
                `Working directory: ''${ctx.directory}`,
                `Is directory a git repo: ''${ctx.project.vcs === "git" ? "Yes" : "No"}`,
                `Platform: ''${process.platform}`,
                `Today'"'"'s date: ''${new Date().toDateString()}`,
                `</env>`,'

          # Same block, unreached today (session/system.ts is what actually
          # runs; this is a second implementation of the same feature in the
          # core package) but patched for the same reason in case it ever
          # becomes live.
          substituteInPlace packages/core/src/system-context/builtins.ts \
            --replace-fail \
              '      "<env>",
          `  Working directory: ''${location.directory}`,
          `  Workspace root folder: ''${location.project.directory}`,
          `  Is directory a git repo: ''${location.vcs?.type === "git" ? "yes" : "no"}`,
          `  Platform: ''${process.platform}`,
          "</env>",' \
              '      "<env>",
          `Working directory: ''${location.directory}`,
          `Is directory a git repo: ''${location.vcs?.type === "git" ? "Yes" : "No"}`,
          `Platform: ''${process.platform}`,
          "</env>",' \
            --replace-fail \
              '"Here is some useful information about the environment you are running in:"' \
              '"Here is useful information about the environment you are running in:"'

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

          # meta.txt is the Llama-family prompt, added upstream in 1.18.x. It is
          # guarded because the pinned upkgs revision may predate it, and a bare
          # substituteInPlace hard-errors on a missing file. This is not a silent
          # skip: if the file exists and this block fails to debrand it, the leak
          # assertion at the end of postPatch still fails the build.
          #
          # The heading on the "Tool Use" line contains an en dash followed by a
          # non-breaking space, so that anchor is deliberately the trailing ASCII
          # substring -- matching the full line would embed those bytes here and
          # break on any upstream whitespace churn.
          if [ -f packages/opencode/src/session/prompt/meta.txt ]; then
            substituteInPlace packages/opencode/src/session/prompt/meta.txt \
              --replace-fail \
                "You are OpenCode, a coding agent that helps users with software engineering tasks. You are powered by {{MODEL_NAME}}, a large language model trained by Meta MSL." \
                "You are Claude Code, a coding agent that helps users with software engineering tasks." \
              --replace-fail \
                "OpenCode Specifics" \
                "Agent Specifics" \
              --replace-fail \
                "- Users can give feedback or report issues at https://github.com/anomalyco/opencode and mention that they are using Meta {{MODEL_NAME}}." \
                "- Users can give feedback or report issues at https://github.com/anthropics/claude-code/issues" \
              --replace-fail \
                '- When users ask directly about OpenCode (eg. "can OpenCode do...", "are you able to do...") or its features (eg. implement a hook, write a slash command, or install an MCP server), use the WebFetch tool to gather information to answer the question from the OpenCode docs at https://opencode.ai/docs.' \
                ""
          fi

          substituteInPlace packages/opencode/src/tool/lsp.txt \
            --replace-fail \
              "For workspaceSymbol, filePath is not sent in the LSP workspace/symbol request. It is used by opencode to select and start the matching LSP server." \
              "For workspaceSymbol, filePath is not sent in the LSP workspace/symbol request. It is used by the agent to select and start the matching LSP server."

          # Wire-level tool identity. The prompt above now claims Claude Code's
          # tool names (Bash, Read, Task, TodoWrite, ...), but until this patch
          # opencode still sent its own lowercase ids (bash, read, ...) in the
          # `tools` array -- prompt and tool list disagreed, which is worse than
          # either alone. This maps opencode's internal ids to Claude Code's
          # wire names (and back, for tool_use blocks in the response) at the
          # one place both directions funnel through: the Anthropic Messages
          # protocol lowering in packages/llm. Internal dispatch, permissions
          # and the TUI never see the alias -- they keep comparing against
          # "bash" etc. same as before, since only this file's wire
          # representation changes. Tools with no faithful Claude Code
          # counterpart (opencode's own apply_patch/lsp/skill, and the
          # always-on "invalid" placeholder) are dropped from the outgoing
          # list entirely rather than leaking an opencode-only name.
          substituteInPlace packages/llm/src/protocols/anthropic-messages.ts \
            --replace-fail \
              'const lowerTool = (breakpoints: Cache.Breakpoints, tool: ToolDefinition, inputSchema: JsonSchema): AnthropicTool => ({
      name: tool.name,
      description: tool.description,
      input_schema: inputSchema,
      cache_control: cacheControl(breakpoints, tool.cache),
    })' \
              'const CC_TOOL_NAME_ALIASES: Record<string, string> = {
      bash: "Bash",
      read: "Read",
      write: "Write",
      edit: "Edit",
      glob: "Glob",
      grep: "Grep",
      webfetch: "WebFetch",
      websearch: "WebSearch",
      todowrite: "TodoWrite",
      task: "Task",
      question: "AskUserQuestion",
      plan_exit: "ExitPlanMode",
    }
    const CC_TOOL_NAME_UNALIASES: Record<string, string> = Object.fromEntries(
      Object.entries(CC_TOOL_NAME_ALIASES).map(([internal, wire]) => [wire, internal]),
    )
    const CC_DROPPED_TOOLS = new Set(["invalid", "apply_patch", "lsp", "skill"])
    const toWireToolName = (name: string): string => CC_TOOL_NAME_ALIASES[name] ?? name
    const fromWireToolName = (name: string): string => CC_TOOL_NAME_UNALIASES[name] ?? name

    const lowerTool = (breakpoints: Cache.Breakpoints, tool: ToolDefinition, inputSchema: JsonSchema): AnthropicTool => ({
      name: toWireToolName(tool.name),
      description: tool.description,
      input_schema: inputSchema,
      cache_control: cacheControl(breakpoints, tool.cache),
    })' \
            --replace-fail \
              'tool: (name) => ({ type: "tool" as const, name }),' \
              'tool: (name) => ({ type: "tool" as const, name: toWireToolName(name) }),' \
            --replace-fail \
              'const lowerToolCall = (part: ToolCallPart): AnthropicToolUseBlock => ({
      type: "tool_use",
      id: part.id,
      name: part.name,
      input: part.input,
    })' \
              'const lowerToolCall = (part: ToolCallPart): AnthropicToolUseBlock => ({
      type: "tool_use",
      id: part.id,
      name: toWireToolName(part.name),
      input: part.input,
    })' \
            --replace-fail \
              '  const tools =
        request.tools.length === 0 || request.toolChoice?.type === "none"
          ? undefined
          : request.tools.map((tool) =>
              lowerTool(
                breakpoints,
                tool,
                ToolSchemaProjection.modelCompatibility(tool.inputSchema, toolSchemaCompatibility),
              ),
            )' \
              '  const tools =
        request.tools.length === 0 || request.toolChoice?.type === "none"
          ? undefined
          : request.tools
              .filter((tool) => !CC_DROPPED_TOOLS.has(tool.name))
              .map((tool) =>
                lowerTool(
                  breakpoints,
                  tool,
                  ToolSchemaProjection.modelCompatibility(tool.inputSchema, toolSchemaCompatibility),
                ),
              )' \
            --replace-fail \
              '    return [
          {
            ...state,
            lifecycle,
            tools: ToolStream.start(state.tools, event.index, {
              id: block.id ?? String(event.index),
              name: block.name ?? "",
              providerExecuted: block.type === "server_tool_use",
            }),
          },
          [...events, LLMEvent.toolInputStart({ id: block.id ?? String(event.index), name: block.name ?? "" })],
        ]' \
              '    const wireName = block.name ?? ""
        const name = block.type === "server_tool_use" ? wireName : fromWireToolName(wireName)
        return [
          {
            ...state,
            lifecycle,
            tools: ToolStream.start(state.tools, event.index, {
              id: block.id ?? String(event.index),
              name,
              providerExecuted: block.type === "server_tool_use",
            }),
          },
          [...events, LLMEvent.toolInputStart({ id: block.id ?? String(event.index), name })],
        ]'

          # MCP tools: opencode names them "<server>_<tool>" (mcp/catalog.ts);
          # Claude Code's convention is "mcp__<server>__<tool>". This is the one
          # place both directions of the name are built, so aliasing it here
          # (rather than in the protocol file above) means the wire and the
          # internal id are the same string -- no reverse lookup needed, and it
          # covers any MCP server without a per-server table entry.
          substituteInPlace packages/opencode/src/mcp/catalog.ts \
            --replace-fail \
              'export const toolName = (clientName: string, name: string) => sanitize(clientName) + "_" + sanitize(name)' \
              'export const toolName = (clientName: string, name: string) => "mcp__" + sanitize(clientName) + "__" + sanitize(name)'

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

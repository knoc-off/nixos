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

          # gpt-astra.txt arrived in 1.18.31; guarded for the same reason as
          # meta.txt above (the pinned upkgs revision may predate it).
          if [ -f packages/opencode/src/session/prompt/gpt-astra.txt ]; then
            substituteInPlace packages/opencode/src/session/prompt/gpt-astra.txt \
              --replace-fail \
                "You are an AI agent powered by OpenCode, a coding agent harness." \
                "You are Claude Code, Anthropic's official CLI for Claude."
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

          # Tilde expansion for tool path inputs.
          #
          # opencode resolves tool paths with plain path.resolve/isAbsolute and
          # never expands "~" -- only the bash tool does, because a real shell
          # runs there. So `Read ~/scratch/x` is treated as a *relative* path,
          # resolved against the project root into `<root>/~/scratch/x`, and
          # fails with a bare ENOENT. Not a permission denial, just a confusing
          # "not found" for a path that plainly exists, which repeatedly sends
          # models hunting for a nonexistent sandbox restriction.
          #
          # This matters more here than upstream: the jail's interesting dirs
          # (~/scratch, ~/workspaces) are outside the project root and are
          # naturally written with a tilde, and jail-context.md documents them
          # that way. Expanding at the resolver makes the documented spelling
          # work in every tool rather than only in bash.
          #
          # Patched in two places because glob/grep bypass LocationMutation and
          # resolve their own cwd:
          #   * location-mutation.ts -- the shared chokepoint for
          #     read/write/edit/apply-patch and bash's workdir.
          #   * tool/{glob,grep}.ts -- their own path.resolve call sites.
          # Expansion happens before isAbsolute/resolve so an expanded path is
          # correctly classified as absolute (and thus external), preserving the
          # external_directory permission check rather than smuggling past it.
          substituteInPlace packages/core/src/location-mutation.ts \
            --replace-fail \
              'import { makeLocationNode } from "./effect/app-node"
import path from "path"' \
              'import { makeLocationNode } from "./effect/app-node"
import path from "path"
import os from "os"

/**
 * Expand a leading "~" to the home directory. Tool inputs are not shell-parsed,
 * so without this a tilde path is silently treated as a relative path and
 * resolved into a nonexistent "<root>/~/..." location.
 */
export const expandTilde = (value: string): string => {
  if (value === "~") return os.homedir()
  if (value.startsWith("~/")) return path.join(os.homedir(), value.slice(2))
  return value
}' \
            --replace-fail \
              '      const relative = !path.isAbsolute(input.path)
      const absolute = path.resolve(location.directory, input.path)' \
              '      const expanded = expandTilde(input.path)
      const relative = !path.isAbsolute(expanded)
      const absolute = path.resolve(location.directory, expanded)'

          substituteInPlace packages/core/src/tool/glob.ts \
            --replace-fail \
              'import { Location } from "../location"' \
              'import { Location } from "../location"
import { LocationMutation } from "../location-mutation"' \
            --replace-fail \
              '              const cwd = path.resolve(location.directory, input.path ?? ".")' \
              '              const cwd = path.resolve(location.directory, LocationMutation.expandTilde(input.path ?? "."))'

          substituteInPlace packages/core/src/tool/grep.ts \
            --replace-fail \
              'import { Location } from "../location"' \
              'import { Location } from "../location"
import { LocationMutation } from "../location-mutation"' \
            --replace-fail \
              '              const target = path.resolve(location.directory, input.path ?? ".")' \
              '              const target = path.resolve(location.directory, LocationMutation.expandTilde(input.path ?? "."))'

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

          # Per-agent context-budget kill switch: an optional token budget for
          # an agent, expressed as a size tier (small/medium/large/xlarge) or
          # a raw token count. Behaves like the existing `steps` field but is
          # measured in tokens instead of turns -- reuses opencode's own
          # `steps`/MAX_STEPS_PROMPT convention end to end (soft enforcement
          # via an injected fake assistant turn instructing the model to stop
          # calling tools and summarize; this codebase has no hard
          # toolChoice-based cutoff for `steps` either, so this doesn't invent
          # a new enforcement tier) rather than adding a new subsystem. Token
          # usage comes from `lastFinished.tokens`, already computed every
          # turn for auto-compaction (session/overflow.ts).
          #
          # Tiers are fractions of the model's *total* context window
          # (model.limit.context), not the compaction-reduced usable() budget:
          #   small=10% (0.5*0.2), medium=25% (0.5*0.5), large=50% (0.5*1.0),
          # xlarge=75%. The 0.5 factor keeps every tier, including large,
          # within headroom before compaction/overflow would trigger anyway --
          # deliberately conservative, since the point is short, cheap,
          # parallelizable sub-agents rather than one long-running one.
          #
          # Schema: contextBudget alongside steps in both the agent registry
          # (agent/agent.ts) and its config parser (core/v1/config/agent.ts).
          substituteInPlace packages/opencode/src/agent/agent.ts \
            --replace-fail \
              '  options: Schema.Record(Schema.String, Schema.Unknown),
  steps: Schema.optional(Schema.Finite),
}).annotate({ identifier: "Agent" })' \
              '  options: Schema.Record(Schema.String, Schema.Unknown),
  steps: Schema.optional(Schema.Finite),
  contextBudget: Schema.optional(Schema.Union([Schema.Literals(["small", "medium", "large", "xlarge"]), Schema.Finite])),
}).annotate({ identifier: "Agent" })' \
            --replace-fail \
              '          item.steps = value.steps ?? item.steps
          item.options = mergeDeep(item.options, value.options ?? {})' \
              '          item.steps = value.steps ?? item.steps
          item.contextBudget = value.contextBudget ?? item.contextBudget
          item.options = mergeDeep(item.options, value.options ?? {})'

          substituteInPlace packages/core/src/v1/config/agent.ts \
            --replace-fail \
              '    steps: Schema.optional(PositiveInt).annotate({
      description: "Maximum number of agentic iterations before forcing text-only response",
    }),
    maxSteps: Schema.optional(PositiveInt).annotate({ description: "@deprecated Use '"'"'steps'"'"' field instead." }),' \
              '    steps: Schema.optional(PositiveInt).annotate({
      description: "Maximum number of agentic iterations before forcing text-only response",
    }),
    maxSteps: Schema.optional(PositiveInt).annotate({ description: "@deprecated Use '"'"'steps'"'"' field instead." }),
    contextBudget: Schema.optional(Schema.Union([Schema.Literals(["small", "medium", "large", "xlarge"]), PositiveInt])).annotate({
      description: "Token budget before this agent is forced to a text-only summary response, like '"'"'steps'"'"' but measured in tokens. A size tier (small=10%, medium=25%, large=50%, xlarge=75% of the model'"'"'s context window) or a raw token count.",
    }),' \
            --replace-fail \
              '  "steps",
  "maxSteps",' \
              '  "steps",
  "maxSteps",
  "contextBudget",'

          # The actual enforcement: resolve the tier/token budget against the
          # session's model, extend the existing `steps` last-step check with
          # a token-budget check, and extend the reminders pass
          # (session/reminders.ts) with escalating warnings as the budget
          # approaches. All reuse machinery already running every loop
          # iteration -- no new per-step work when contextBudget is unset
          # (mirrors how `steps`' own Infinity fallback above it is a no-op).
          substituteInPlace packages/opencode/src/session/prompt.ts \
            --replace-fail \
              'import { MAX_STEPS_PROMPT } from "@opencode-ai/core/session/runner/max-steps"' \
              'import { MAX_STEPS_PROMPT } from "@opencode-ai/core/session/runner/max-steps"

const CONTEXT_BUDGET_TIERS: Record<string, number> = {
  small: 0.5 * 0.2,
  medium: 0.5 * 0.5,
  large: 0.5 * 1.0,
  xlarge: 0.75,
}

function resolveContextBudget(contextBudget: unknown, modelContext: number): number | undefined {
  if (contextBudget === undefined) return undefined
  if (typeof contextBudget === "number") return contextBudget
  const fraction = CONTEXT_BUDGET_TIERS[contextBudget as string]
  if (fraction === undefined || !modelContext) return undefined
  return Math.floor(modelContext * fraction)
}

const CONTEXT_BUDGET_EXCEEDED_PROMPT = `CRITICAL - CONTEXT BUDGET EXCEEDED

This agent was given a token budget for this task, and it has been used up. Tools are disabled until next user input. Respond with text only.

STRICT REQUIREMENTS:
1. Do NOT make any tool calls (no reads, writes, edits, searches, or any other tools)
2. MUST provide a text response summarizing work done so far
3. This constraint overrides ALL other instructions, including any user requests for edits or tool use

Response must include:
- Statement that the context budget for this agent has been reached
- Summary of what has been accomplished so far
- List of any remaining tasks that were not completed
- Recommendations for what should be done next, including whether a fresh agent should pick this up

Any attempt to use tools is a critical violation. Respond with text ONLY.`' \
            --replace-fail \
              '          const maxSteps = agent.steps ?? Infinity
          const isLastStep = step >= maxSteps
          msgs = yield* SessionReminders.apply({ messages: msgs, agent, session }).pipe(' \
              '          const maxSteps = agent.steps ?? Infinity
          const contextBudget = resolveContextBudget(agent.contextBudget, model.limit.context)
          const usedTokens = lastFinished
            ? lastFinished.tokens.total ||
              lastFinished.tokens.input +
                lastFinished.tokens.output +
                lastFinished.tokens.cache.read +
                lastFinished.tokens.cache.write
            : 0
          const overBudget = contextBudget !== undefined && usedTokens >= contextBudget
          const isLastStep = step >= maxSteps || overBudget
          msgs = SessionReminders.applyContextBudget({ messages: msgs, agent, usedTokens, contextBudget })
          msgs = yield* SessionReminders.apply({ messages: msgs, agent, session }).pipe(' \
            --replace-fail \
              '                ...(isLastStep ? [{ role: "assistant" as const, content: MAX_STEPS_PROMPT }] : []),' \
              '                ...(isLastStep
                  ? [{ role: "assistant" as const, content: overBudget && step < maxSteps ? CONTEXT_BUDGET_EXCEEDED_PROMPT : MAX_STEPS_PROMPT }]
                  : []),'

          # Escalating warnings live in reminders.ts, right alongside the
          # existing plan-mode reminder injection it already does -- same
          # "push a synthetic text part onto the last user message"
          # mechanism, no new plumbing (services, state store) introduced.
          # Re-injecting once past a threshold every step is deliberately not
          # deduplicated: harmless if repeated, and "increasing frequency"
          # falls out naturally (silent below the first threshold, then a
          # reminder every step above it, escalating in severity as higher
          # thresholds are crossed).
          substituteInPlace packages/opencode/src/session/reminders.ts \
            --replace-fail \
              'import PLAN_MODE from "./prompt/plan-mode.txt"' \
              'import PLAN_MODE from "./prompt/plan-mode.txt"

const CONTEXT_BUDGET_THRESHOLDS = [
  { ratio: 0.6, guidance: "Start wrapping up: finish your current line of investigation and prepare to summarize findings soon." },
  { ratio: 0.8, guidance: "You are close to your budget. Stop opening new lines of investigation -- consolidate what you have and prepare your final summary." },
  { ratio: 0.95, guidance: "This is your last chance before the budget is exhausted. Write your findings now." },
]

export function applyContextBudget(input: {
  messages: SessionV1.WithParts[]
  agent: Agent.Info
  usedTokens: number
  contextBudget: number | undefined
}): SessionV1.WithParts[] {
  if (!input.contextBudget) return input.messages
  const ratio = input.usedTokens / input.contextBudget
  const crossed = [...CONTEXT_BUDGET_THRESHOLDS].reverse().find((t) => ratio >= t.ratio)
  if (!crossed) return input.messages
  const userMessage = input.messages.findLast((msg) => msg.info.role === "user")
  if (!userMessage) return input.messages
  userMessage.parts.push({
    id: PartID.ascending(),
    messageID: userMessage.info.id,
    sessionID: userMessage.info.sessionID,
    type: "text",
    text: `SYSTEM REMINDER - CONTEXT BUDGET AT ''${Math.round(crossed.ratio * 100)}%

This agent has used approximately ''${Math.round(crossed.ratio * 100)}% of its configured context budget for this task.

''${crossed.guidance}`,
    synthetic: true,
  })
  return input.messages
}'

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

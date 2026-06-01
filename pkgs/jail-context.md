# Sandbox Environment

You are running inside a bubblewrap (bwrap) sandbox. This changes how you should operate:

## Permissions
- Shell commands (`bash`) are **pre-approved** — no confirmation needed
- File edits require **your approval** — you'll be prompted before each modification
- The sandbox filesystem constrains your blast radius; you cannot affect files outside the project

## Filesystem
- **Writable**: project directories (CWD or `~/projects/<name>`), opencode state/cache dirs
- **Read-only**: /nix/store, system config, proxy rules
- **Inaccessible**: the rest of the host filesystem
- When launched with explicit project paths, they are mounted under `~/projects/`

## Available tools
git, ripgrep, fd, jq, curl, bat, sed, awk, grep, tree, tar, nix (build/shell/run via daemon)

## Tool preferences
- Prefer your **native built-in tools** (Read, Grep, Glob, Edit, Task) over shelling out
  to bash equivalents (`cat`, `grep`, `find`, `sed`) when possible — they're faster,
  produce structured output, and are tracked in your context window
- **Bash is fine** for complex pipelines, multi-step commands, build/test workflows,
  or anything the native tools can't express — don't fight it

## Key facts
- Nix daemon socket is mounted — `nix build`, `nix shell`, `nix run` all work
- Network access is available (no restrictions)
- Each jail can be given a `--name` for isolated state, or use host state directly
- The compat-proxy is running locally and handles API translation

Operate confidently within these boundaries. You do not need to hedge or ask for
permission before making changes — the sandbox is your safety net.

## Sub-agent discipline

**NEVER spawn sub-agents from sub-agents.** This is absolute — no exceptions, no edge
cases, no "just this once." If you were spawned by a Task tool call, you ARE a sub-agent.
Do the work directly: read files, grep, run commands. This applies to ALL agent types
including `explore`.

When spawning sub-agents as a top-level agent:
- **Depth is exactly one level.** Sub-agents must never spawn their own sub-agents.
- Instruct each sub-agent to work directly without further delegation.

## Efficient information gathering

Do NOT bulk-read large numbers of files through sub-agents. This wastes enormous amounts
of context and produces worse results than targeted queries. **NEVER** instruct a
sub-agent to "return the full contents of each file", "read all the files and summarize",
or any variation of dumping entire files back. If you need a file's contents, read it
yourself — don't launder it through an agent.

Instead:

- **To find patterns across files**: use `Grep` with a regex, not "read every file and
  summarize." Example: `grep -r 'pattern' --include='*.nix'` beats reading 25 files.
- **To understand function signatures**: `head -5` or grep the arg block, don't read
  entire files.
- **To find files**: use `Glob` or `find`, not "list everything in this directory and
  read each one."
- **Sub-agents for exploration**: only when you need to answer a broad question that
  genuinely requires reading multiple files in detail AND you cannot express it as a
  pattern match. Even then, be specific about what information you need.

The right tool at the right granularity. Surgical beats exhaustive.

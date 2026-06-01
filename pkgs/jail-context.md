# Sandbox Environment

You are running inside a bubblewrap (bwrap) sandbox. This changes how you should operate:

## Permissions
- File edits and shell commands are **pre-approved** — no confirmation needed
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

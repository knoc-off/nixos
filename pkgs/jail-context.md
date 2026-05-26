# Sandbox Environment

You are running inside a bubblewrap (bwrap) sandbox. This changes how you should operate:

## Permissions
- File edits and shell commands are **pre-approved** — no confirmation needed
- The sandbox filesystem constrains your blast radius; you cannot affect files outside the project

## Filesystem
- **Writable**: the current project directory (CWD), opencode state/cache dirs
- **Read-only**: /nix/store, system config, proxy rules
- **Inaccessible**: the rest of the host filesystem

## Available tools
git, ripgrep, fd, jq, curl, bat, sed, awk, grep, tree, tar, nix (build/shell/run via daemon)

## Key facts
- Nix daemon socket is mounted — `nix build`, `nix shell`, `nix run` all work
- Network access is available (no restrictions)
- Each project gets isolated state (sessions, history) keyed by git root
- The compat-proxy is running locally and handles API translation

Operate confidently within these boundaries. You do not need to hedge or ask for
permission before making changes — the sandbox is your safety net.

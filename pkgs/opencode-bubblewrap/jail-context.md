# Sandbox Environment

You are running inside a bubblewrap (bwrap) sandbox. This changes how you should operate:

## Permissions

- Shell commands (`bash`) are **pre-approved** — no confirmation needed
- File edits require **your approval** — you'll be prompted before each modification
- The sandbox filesystem constrains your blast radius; you cannot affect files outside the project

## Filesystem

- **Writable**: project directories, `~/scratch`, `~/workspaces`, opencode state/cache dirs
- **Read-only**: /nix/store, system config, proxy rules
- **Inaccessible**: the rest of the host filesystem
- Projects are mounted at **their real host path** — a repo the host knows as
  `~/work/foo` is `~/work/foo` in here too, with the same absolute path. File
  references you produce are therefore directly usable on the host, and host-side
  tools (language servers in particular) understand the paths you send them.
- With a single project, opencode's root is that project directly. With
  multiple projects, the root is their deepest common ancestor (often `~`
  itself), and each project appears as a subdirectory beneath it — `@`-complete
  and the file index reach all of them, but only from that shared root down.
  If the ancestor isn't itself a git repo, opencode's file index and
  `.gitignore` handling degrade (fewer files indexed, paths shown from `/`) —
  a warning is printed at startup when this happens.

## Scratch workspace — `~/scratch/`

- `~/scratch/` is **persistent across sessions**: anything you write there survives
  restarts of this jail (per-`--name`, or a shared dir for unnamed jails).
- `/tmp` is a tmpfs and is **wiped every session** — do NOT use it for anything you
  want to keep.
- Put throwaway scripts, experiments, clones, notes, and generated artifacts under
  `~/scratch/` instead of `/tmp`, so useful work persists.
- Everything else in `~` is a tmpfs and is discarded when the session ends, apart
  from explicitly shared caches (cargo registry, nix, pnpm, npm, bun, uv).
- `~` works in file tool paths (Read/Glob/Grep/Edit/Write) as well as in bash --
  `~/scratch/foo` and `/home/you/scratch/foo` are equivalent everywhere.

## Git worktrees — `~/workspaces/`

- `~/workspaces/` is a **real host directory**, bound at the same path, shared by
  every jail (not per-`--name` like `~/scratch`) — a worktree created here from
  one session is immediately visible on the host and from any other session.
- Use it for `git worktree add ~/workspaces/<name> <branch>` when you need a
  second checkout of a repo (e.g. to work on two branches at once without
  disturbing the main checkout). Because the whole directory is mounted, new
  worktrees created inside it appear automatically — no jail restart, and no
  need to pass them as explicit projects.
- Unlike project directories, `~/workspaces/` is not automatically part of
  opencode's `@`-completable root unless it happens to fall under the deepest
  common ancestor of your mounted projects. It's always reachable by path in
  the shell either way.

## Host directory grants — `host_mount`

- Need to read files on the host outside the mounted projects? `host_mount`
  binds a host directory at `~/scratch/granted/<name>`, where the normal file
  tools (Read, Grep, Glob) work on it. Read-only by default; pass `write: true`
  to mount it read-write. Takes effect immediately — no restart. The user
  approves each grant.
- Re-granting a name that is already mounted remounts it, so switching a grant
  from read-only to writable is just another `host_mount` call with
  `write: true` — no unmount step.
- The grant is at a _translated_ path, not the real host path. For a repo you
  want to edit or run an LSP against, use `~/workspaces` instead — that keeps
  host-identical paths, which language servers and your own file references
  depend on.
- Grants are per-session and unmounted on exit.

## Per-directory environments — direnv

- direnv is active in the shell. `cd`-ing into a project dir containing an `.envrc`
  auto-loads its environment (nix-direnv's `use flake` is supported).
- For a new/edited `.envrc`, run `direnv allow` to authorize it. Authorizations are
  persisted across sessions, so you only allow once per project.

## Python scripts — `script_exec`

- `script_exec` runs a Python script with dependencies resolved via Nix — no
  pip, no venv. Declare `packages` (python3Packages attrs: `requests`, `numpy`,
  `beautifulsoup4`, ...) and `nixPackages` (system tools on PATH: `ffmpeg`, ...)
  and they are provided automatically. Prefer it over hand-rolling
  `nix shell` + heredocs in bash for anything beyond a one-liner.
- Before writing a new script, call `script_exec` with `list: true` (or
  `list: "keyword"` to filter). It's a header scan, not a run — check whether
  a saved script already does this, or is close enough to extend instead of
  duplicating.
- Pass `script` alone for a throwaway run (kept under
  `~/scratch/scripts/.temp/`, not deleted — promote a useful one by moving it
  into `~/scratch/scripts/`). Add `name` + `description` to save it to
  `~/scratch/scripts/<name>.py` and run it. Pass `name` alone to re-run a
  saved script.
- Saved scripts carry their description and deps in a `# /// script-exec`
  header inside the file — plain files, so `Edit` can change either
  (including deps) directly. `~/scratch/scripts/` is a git repo; every save
  is a commit, so pass `message` describing what changed (e.g. "extended
  fxdbg to accept a port") and an overwrite is always recoverable via git
  history.

## Available tools

git, ripgrep, fd, jq, curl, bat, sed, awk, grep, tree, tar, nix (build/shell/run via daemon)

- `, <program>` (comma) runs any nixpkgs program by name without installing it
  or knowing its attribute path, e.g. `, magick photo.png`, `, cowsay hi`.

## Windows VM helpers (explicit use only)

- `windows-vm-ssh [cmd...]` — run a command on (or open a shell into) the local
  Windows VM over SSH. Thin wrapper around `sshpass + ssh` to 127.0.0.1:2223.
- `windows-vm-scp <src> <dst>` — copy files to/from the Windows VM. Thin wrapper
  around `sshpass + scp`; args pass straight through, so you supply the full
  destination, e.g.
  `windows-vm-scp ./app.exe vmadmin@127.0.0.1:'C:/Users/vmadmin.TEMPLATE--XXXX/Desktop/'`
- **Only use these when the user explicitly asks you to interact with the Windows
  VM.** Do not use them otherwise.

## Git

- **Committing is fine, pushing is not.** No auth key, token or credential helper is
  mounted, and git-over-SSH is disabled — pushes will fail. Commit freely and leave
  pushing to the user, who does it from the host after reviewing your work.
- Cloning over HTTPS works; cloning over SSH does not.

## Tool preferences

- **Investigating? Ask "can a dumber agent do this?" -- if yes, dispatch
  `explore-quick`; if it needs finesse, `explore-mid`** (see "Explore tiers"
  below). Searching the tree yourself is the exception, not the default.
- When you do work directly, prefer your **native built-in tools** (Read, Edit, Task)
  over shelling out to bash equivalents (`cat`, `sed`) — they're faster, produce
  structured output, and are tracked in your context window
- **Bash is fine** for complex pipelines, multi-step commands, build/test workflows,
  or anything the native tools can't express — don't fight it

## Key facts

- Nix daemon socket is mounted — `nix build`, `nix shell`, `nix run` all work
- Network access is available (no restrictions)
- Each jail can be given a `--name` for isolated state, or use host state directly
- The compat-proxy is running locally and handles API translation

Operate confidently within these boundaries. You do not need to hedge or ask for
permission before making changes — the sandbox is your safety net.

## Reading files — locate, don't page

Applies to every agent, including when you are the one dispatched to do a
lookup.

**Never page through a large file to find something in it.** Grep for the
answer, then Read a narrow window around the hits. Reading a 3000-line log in
2000-line pages to find one stack trace costs ~40x what the answer is worth and
will exhaust your context budget before you get there.

- Know the file, need the content -> Read it.
- Know the file, need one thing _in_ it -> grep first, then Read around the hit.
- Don't know the file -> grep the tree.

Check the size before a blind Read (`wc -l`, `wc -c`). Over a few hundred
lines, locate first.

## Explore tiers — default reflex for ALL investigation

Three read-only exploration sub-agents. Each has a tight context budget and
hands back one condensed answer, so use them freely.

**Known path + known target = `Read`, never `Task`.** If you can name the file,
you are not investigating -- you are reading. Dispatching for contents you
could `Read` spends two context windows moving bytes you already knew how to
find, and relays them through a model that can silently reformat them.

| Agent           | Model      | Use for                                                                                |
| --------------- | ---------- | -------------------------------------------------------------------------------------- |
| `explore-quick` | Sonnet 4.5 | **Default.** Locating files, grep/glob, "where is X", confirming an assumption          |
| `explore-mid`   | Sonnet 5   | Lookups needing real reasoning: tracing logic across files, picking between candidates |
| `explore-deep`  | Opus 5     | Rare. Ambiguous scope, subtle cross-cutting bugs, synthesis a cheap model would botch  |

**Any time you catch yourself searching or exploring, ask: "could a dumber
agent do this?"**

- Yes -> `explore-quick`. Dispatch it, don't do it.
- "This needs a bit more finesse" -> `explore-mid`. Genuinely good, and
  routinely under-used: reach for it the moment a lookup needs judgement
  rather than a pattern match. It is a first choice, not just an escalation.
- Only if a cheap model would plausibly botch the synthesis -> `explore-deep`.

So: if you are about to run Grep, Glob, or a read-only `find`/`ls`/`rg` to
figure something out, dispatch instead. Searching yourself is the exception
that needs a reason. This governs _searching_; reading a file you have already
located is not searching.

**The exception is the genuine one-shot.** One `rg` whose output you will read
and be done with -- "does this string appear anywhere", "how many call sites"
-- is not worth an agent. Run it. Delegate what will turn into a goose chase:
a search whose _results tell you what to search for next_. Grep the symbol ->
find the file -> read it -> discover the real definition is elsewhere -> grep
again. That chain is the agent's job, and each hop you take yourself dumps
intermediate output you will never need into your context. If you cannot say
in advance that one command answers it, dispatch.

A lookup that "feels hard" is usually just a lookup -- when in doubt between
two tiers, take the cheaper one and escalate on a bad answer. Reserve
`explore-deep` for narrow, well-posed questions -- sweep with `explore-quick`
and hand it the findings to judge.

First pass for:

- "where is X defined / where is X used / does X exist"
- finding files by name, pattern, or extension
- keyword and regex searches across the tree
- reconnaissance before ANY non-trivial edit -- find the call sites first
- confirming an assumption before you act on it
- any question you cannot already answer from what is in your context

Do it yourself only when:

- you already know the exact file and just need to Read it
- it is a single trivial lookup in a file you have open
- one command answers it outright and you know that before running it
- you are executing (editing, building, running), not investigating
- the work is a real command with side effects (git, nix build, tests)

## Batch sub-agents — fan out by default

**Put every independent Task call in a SINGLE message.** Calls in one message
run in parallel; calls split across messages run one after another.

Default to a batch of **3-5** whenever a task opens with more than one unknown.
List what you don't know, then dispatch it all at once:

- "Where is X defined?" + "Who calls X?" + "Are there tests for X?" -> 3 calls, one message.
- Auditing N files against a rule -> one call per file or group, all at once.
- Investigating a bug -> "where is the error raised" + "where is the config read" + "what does the caller pass" together.
- Comparing two implementations -> one agent per implementation, in parallel.

Mix tiers freely in one batch: one `explore-mid` on the hard part alongside
three `explore-quick` calls on the lookups.

Go sequential only when a question cannot be written until an earlier answer
arrives. Usually you can guess both branches and ask about both at once.

Split by _question_, not by file count. Each call needs its own specific
deliverable.

**Verify before you act.** A cheap model reporting "X doesn't exist" is weak
evidence, and agreement between agents does not make it strong. Confirm
anything load-bearing -- an exact string you are about to patch, a "no other
call sites" conclusion -- yourself. Delegate the search; own the conclusion.

## Sub-agent discipline

Read-only exploration tiers cannot spawn sub-agents; edit, write and `task`
are denied to them.

Don't restate that in dispatch prompts. "Read-only, do not edit files, do not
delegate" is wasted text -- every line of the prompt should be the question.

## How to delegate well

**Name the goal, not the tool.** "Find the crash cause in log.txt" leaves the
agent free to grep; "Read log.txt and find the crash cause" orders it to page
through a 500KB file. Never open a dispatch with "Read <file>" unless you
genuinely want the whole file in that agent's context.

Bad: "report the full source of class X, both method signatures and bodies,
and the import block." That is `Read`, laundered through a sub-agent: slower,
lossier, and twice the tokens.

Delegate the _search_, not the _reading_. Ask for answers, locations, and small
exact snippets. Never ask for bulk file contents -- if you need a whole file,
Read it yourself once you know which one it is. Anything that has to be exact
-- a signature you will pattern-match, a string you will patch -- should not
cross a lossy relay. Delegate the search; own the conclusion.

Ask for:

- **Patterns across files**: "grep for X, report file:line with 2 lines of context."
- **Exact strings for a patch**: the specific lines only, a few at a time.
  A whole function, class, or file is the bulk-contents mistake wearing the
  word "verbatim".
- **Locating things**: "which file defines X" — a path, not a file dump.
- **A specific question**: state exactly what you need back, and how much.

Constraints on what comes _back_ are worth stating; nothing enforces those.
A vague prompt gets a vague, expensive answer.

// OpenCode plugin for script-exec.
// One tool, script_exec: run a Python script with dependencies resolved via
// Nix (python3.withPackages + extra nixpkgs tools on PATH), inside the jail.
//
// Usage shapes:
//   script only          -- throwaway: saved under .temp/, run, kept
//   script + name        -- save to ~/scratch/scripts/<name>.py, then run
//   name only            -- re-run a saved script; deps come from its header
//   list: true/"substr"  -- list (optionally filter) saved scripts by header
//
// Saved scripts are self-contained: dependency + description metadata lives
// in a header block inside the file itself, so a script re-read later (or
// hand-edited with the Edit tool) carries its own metadata -- no sidecar
// state, no lossy round-trip. The header is the single source of truth on
// re-run and on listing.
//
//   # /// script-exec
//   # description = "One line: what it does, and its argv if any"
//   # packages = ["requests"]
//   # nixPackages = ["ffmpeg"]
//   # ///
//
// Deliberately NOT real PEP 723 ("# /// script"): that format declares PyPI
// requirements for uv-style runners, and these are nixpkgs attribute names.
// Claiming the PEP 723 marker with nix attrs would confuse any tool that
// actually speaks it.
//
// The scripts directory is a git repo (initialized lazily). Every save is a
// commit, so an overwrite is recoverable via `git log`/`git show` instead of
// gated behind a refusal flag. Throwaways land in .temp/ (gitignored) so
// scratch noise doesn't pollute history, but keep their header and are never
// deleted outright -- promoting one to a saved script is a single `mv`.

import { createRequire } from "node:module";
import { execFile } from "node:child_process";
import { mkdir, readFile, writeFile, readdir, stat, rm } from "node:fs/promises";
import { homedir } from "node:os";
import { join } from "node:path";
import { promisify } from "node:util";

const run = promisify(execFile);

// Lazy: zod is resolved from opencode's own install, which only exists once
// the plugin actually loads inside the jail. The pure header functions below
// have no such dependency and must import cleanly on their own (see
// test.mjs / the `script-exec` flake check).
function loadZod() {
  const require = createRequire(
    (process.env.HOME || "/root") + "/.config/opencode/package.json"
  );
  return require("zod").z;
}

const SCRIPTS_DIR = join(homedir(), "scratch", "scripts");
const TEMP_DIR = join(SCRIPTS_DIR, ".temp");
const TEMP_KEEP = 20;
// Set by the jail launcher (pkgs/opencode-bubblewrap) to the flake's pinned
// unstable nixpkgs. Not <nixpkgs>: channels/NIX_PATH aren't reliably bound
// inside the jail, and pinning makes runs reproducible against the same
// package set the rest of the agent toolbelt is built from.
const NIXPKGS = process.env.SCRIPT_EXEC_NIXPKGS_PATH || "";

const NAME_RE = /^[A-Za-z0-9_-]+$/;
// Bare (possibly dotted) nixpkgs attribute paths, e.g. "numpy",
// "nodePackages.prettier". This is the only injection surface -- the script
// body is written to a file, never interpolated into the Nix expression --
// so the charset excludes anything that could escape an interpolation.
const ATTR_RE = /^[A-Za-z_][A-Za-z0-9_.'-]*$/;

const HEADER_START = "# /// script-exec";
const HEADER_END = "# ///";
const OUTPUT_CAP = 50000;

export function makeHeader(description, packages, nixPackages) {
  // All three lines always present, even when empty: the metadata must be
  // retrievable from the file alone, not reconstructed from absence.
  return [
    HEADER_START,
    `# description = ${JSON.stringify(description || "")}`,
    `# packages = ${JSON.stringify(packages)}`,
    `# nixPackages = ${JSON.stringify(nixPackages)}`,
    HEADER_END,
  ].join("\n");
}

// Header lookup is whitespace-tolerant: a hand-edited header with trailing
// spaces on the marker line must not silently degrade to "no header found"
// (which then fails one layer away as an unrelated ImportError).
export function parseHeader(source) {
  const lines = source.split("\n");
  const start = lines.findIndex((l) => l.trim() === HEADER_START);
  const out = { description: "", packages: [], nixPackages: [] };
  if (start === -1) return out;
  for (let i = start + 1; i < lines.length; i++) {
    if (lines[i].trim() === HEADER_END) break;
    const mArr = lines[i].match(/^#\s*(packages|nixPackages)\s*=\s*(\[.*\])\s*$/);
    if (mArr) {
      try {
        const arr = JSON.parse(mArr[2]);
        if (Array.isArray(arr)) out[mArr[1]] = arr.map(String);
      } catch {
        // malformed line: ignored, stays empty -- the run will then fail on
        // a missing import, which points straight back at the header
      }
      continue;
    }
    const mDesc = lines[i].match(/^#\s*description\s*=\s*("(?:[^"\\]|\\.)*")\s*$/);
    if (mDesc) {
      try {
        out.description = JSON.parse(mDesc[1]);
      } catch {
        // malformed: stays ""
      }
    }
  }
  return out;
}

export function stripHeader(source) {
  const lines = source.split("\n");
  const start = lines.findIndex((l) => l.trim() === HEADER_START);
  if (start === -1) return source;
  let end = start;
  for (let i = start + 1; i < lines.length; i++) {
    if (lines[i].trim() === HEADER_END) {
      end = i;
      break;
    }
  }
  lines.splice(start, end - start + 1);
  return lines.join("\n").replace(/^\n+/, "");
}

// Prepend header, keeping a shebang line first if present.
export function withHeader(body, description, packages, nixPackages) {
  const stripped = stripHeader(body);
  const header = makeHeader(description, packages, nixPackages);
  if (stripped.startsWith("#!")) {
    const nl = stripped.indexOf("\n");
    const shebang = nl === -1 ? stripped : stripped.slice(0, nl);
    const rest = nl === -1 ? "" : stripped.slice(nl + 1);
    return `${shebang}\n${header}\n${rest}`;
  }
  return `${header}\n${stripped}`;
}

function validateAttrs(names, what) {
  for (const n of names) {
    if (!ATTR_RE.test(n)) {
      throw new Error(`invalid ${what} name: ${JSON.stringify(n)}`);
    }
  }
}

async function buildEnv(packages, nixPackages) {
  validateAttrs(packages, "python package");
  validateAttrs(nixPackages, "nix package");
  if (!NIXPKGS) {
    throw new Error(
      "SCRIPT_EXEC_NIXPKGS_PATH is not set; script_exec is unavailable"
    );
  }
  const pyAttrs = packages.map((p) => `ps.${p}`).join(" ");
  const extraAttrs = nixPackages.map((p) => `pkgs.${p}`).join(" ");
  const expr = `
    let
      pkgs = import ${NIXPKGS} { };
      py = pkgs.python3.withPackages (ps: [ ${pyAttrs} ]);
    in
    pkgs.symlinkJoin { name = "script-exec-env"; paths = [ py ${extraAttrs} ]; }
  `;
  // --impure: import-by-path needs builtins.currentSystem. Fine here -- the
  // inputs (pinned nixpkgs path + validated attr names) are fully determined.
  const { stdout } = await run(
    "nix",
    ["build", "--no-link", "--print-out-paths", "--impure", "--expr", expr],
    { timeout: 600000, maxBuffer: 10 * 1024 * 1024 }
  );
  return stdout.trim().split("\n").pop();
}

function clip(s) {
  if (s.length <= OUTPUT_CAP) return s;
  return s.slice(0, OUTPUT_CAP) + `\n... (output truncated at ${OUTPUT_CAP} chars)`;
}

async function ensureRepo() {
  await mkdir(SCRIPTS_DIR, { recursive: true });
  try {
    await stat(join(SCRIPTS_DIR, ".git"));
  } catch {
    await run("git", ["init", "-q"], { cwd: SCRIPTS_DIR });
    await writeFile(join(SCRIPTS_DIR, ".gitignore"), ".temp/\n");
  }
}

// Never lets a commit failure fail the actual script run -- the repo is a
// safety net, not a gate.
async function commit(message) {
  try {
    await run("git", ["add", "-A", "--", ":!.temp"], { cwd: SCRIPTS_DIR });
    await run("git", ["commit", "-q", "-m", message, "--allow-empty-message"], {
      cwd: SCRIPTS_DIR,
    });
  } catch {
    // e.g. nothing to commit -- fine
  }
}

async function listSaved(filter) {
  let files;
  try {
    files = (await readdir(SCRIPTS_DIR)).filter((f) => f.endsWith(".py"));
  } catch {
    return [];
  }
  const needle = typeof filter === "string" ? filter.toLowerCase() : null;
  const out = [];
  for (const f of files) {
    const name = f.slice(0, -3);
    let description = "";
    try {
      ({ description } = parseHeader(await readFile(join(SCRIPTS_DIR, f), "utf8")));
    } catch {
      continue;
    }
    if (needle && !name.toLowerCase().includes(needle) && !description.toLowerCase().includes(needle)) {
      continue;
    }
    out.push({ name, description });
  }
  out.sort((a, b) => a.name.localeCompare(b.name));
  return out;
}

function formatList(entries) {
  if (!entries.length) return "(no saved scripts match)";
  return entries
    .map((e) => `${e.name} -- ${e.description || "(no description)"}`)
    .join("\n");
}

async function pruneTemp() {
  let files;
  try {
    files = await readdir(TEMP_DIR);
  } catch {
    return;
  }
  if (files.length <= TEMP_KEEP) return;
  const withTimes = await Promise.all(
    files.map(async (f) => {
      const p = join(TEMP_DIR, f);
      const s = await stat(p).catch(() => null);
      return { p, mtime: s ? s.mtimeMs : 0 };
    })
  );
  withTimes.sort((a, b) => b.mtime - a.mtime);
  for (const { p } of withTimes.slice(TEMP_KEEP)) {
    await rm(p, { force: true });
  }
}

export default async (_ctx) => {
  const z = loadZod();
  return {
  tool: {
    script_exec: {
      description:
        "What: run a Python script, dependencies resolved via Nix (nixpkgs " +
        "python3Packages + system tools), no pip/venv. " +
        "When: any Python task beyond a one-liner -- prefer over shelling out " +
        "to `python3 -c` or hand-rolled `nix shell`. Before writing a new " +
        "script, call with `list` to check whether a saved one already does " +
        "this or is close enough to extend. " +
        "Shapes: `script` alone runs once (kept under .temp/ for later " +
        "promotion); `script`+`name`(+`description`) saves to " +
        "~/scratch/scripts/<name>.py and runs it, git-committed; `name` alone " +
        "re-runs a saved script (deps/description come from its in-file " +
        "header); `list` (true, or a substring) returns saved scripts and " +
        "their descriptions without running anything.",
      args: {
        script: z
          .string()
          .optional()
          .describe(
            "Full Python source. Omit to re-run a saved script by name, or " +
              "to list."
          ),
        name: z
          .string()
          .optional()
          .describe(
            "Script name ([A-Za-z0-9_-]). With `script`: save (or overwrite, " +
              "git-committed) then run. Alone: re-run the saved script."
          ),
        description: z
          .string()
          .optional()
          .describe(
            "One-line summary (what it does, argv if any). Required the " +
              "first time a `name` is saved -- this is what `list` shows " +
              "later. Optional on an update; omitted means keep the existing " +
              "one."
          ),
        message: z
          .string()
          .optional()
          .describe(
            "Git commit message for this save, e.g. 'added script that " +
              "diffs IBL configs' or 'extended fxdbg to accept a port'. " +
              "Defaults to a generic add/update message."
          ),
        packages: z
          .array(z.string())
          .optional()
          .describe(
            "python3Packages attribute names to make importable (e.g. " +
              "['requests', 'numpy'])."
          ),
        nixPackages: z
          .array(z.string())
          .optional()
          .describe(
            "Top-level nixpkgs attribute names to put on PATH for the " +
              "script's subprocesses (e.g. ['ffmpeg', 'imagemagick'])."
          ),
        args: z
          .array(z.string())
          .optional()
          .describe("Command-line arguments passed to the script."),
        timeout: z
          .number()
          .optional()
          .describe("Script timeout in seconds (default 120)."),
        list: z
          .union([z.boolean(), z.string()])
          .optional()
          .describe(
            "List saved scripts instead of running anything. `true` lists " +
              "all; a string filters by substring match against name or " +
              "description."
          ),
      },
      async execute(args, context) {
        if (args.list) {
          const entries = await listSaved(
            typeof args.list === "string" ? args.list : null
          );
          return formatList(entries);
        }

        const script = args.script;
        let name = String(args.name || "").trim().replace(/\.py$/, "");
        if (name && !NAME_RE.test(name)) {
          return `Error: invalid name ${JSON.stringify(name)} (allowed: [A-Za-z0-9_-])`;
        }
        if (!script && !name) {
          return "Error: provide `script` (run code), `name` (re-run saved), or `list`";
        }

        let packages = args.packages || [];
        let nixPackages = args.nixPackages || [];
        let scriptPath;
        let label;
        let savedMsg = "";

        if (script) {
          if (name) {
            await ensureRepo();
            scriptPath = join(SCRIPTS_DIR, `${name}.py`);
            let existingDescription = "";
            let isUpdate = false;
            try {
              ({ description: existingDescription } = parseHeader(
                await readFile(scriptPath, "utf8")
              ));
              isUpdate = true;
            } catch {
              // new script
            }
            const description = args.description || existingDescription;
            if (!description) {
              return "Error: `description` is required the first time a script is saved (shows up in `list` later)";
            }
            await writeFile(
              scriptPath,
              withHeader(script, description, packages, nixPackages)
            );
            const commitMsg =
              args.message || (isUpdate ? `update ${name}` : `add ${name}`);
            await commit(commitMsg);
            label = `${name}.py`;
            savedMsg = `saved to ${scriptPath} (${commitMsg}); re-run with name only\n`;
          } else {
            await mkdir(TEMP_DIR, { recursive: true });
            const tempName = `${Date.now()}-${Math.random().toString(36).slice(2)}`;
            scriptPath = join(TEMP_DIR, `${tempName}.py`);
            await writeFile(
              scriptPath,
              withHeader(script, args.description || "", packages, nixPackages)
            );
            await pruneTemp();
            label = `${tempName}.py`;
            savedMsg = `kept at ${scriptPath} -- promote with: mv it into ${SCRIPTS_DIR}/<name>.py\n`;
          }
        } else {
          // Re-run by name: the header inside the file is the single source
          // of truth for deps. Rejecting explicit deps here (rather than
          // merging or ignoring) keeps the stored metadata authoritative.
          if (packages.length || nixPackages.length) {
            return `Error: on a re-run by name, dependencies come from the script's header -- edit ${join(SCRIPTS_DIR, `${name}.py`)} to change them`;
          }
          scriptPath = join(SCRIPTS_DIR, `${name}.py`);
          let source;
          try {
            source = await readFile(scriptPath, "utf8");
          } catch {
            const entries = await listSaved(null);
            return `Error: no saved script ${name}.py in ${SCRIPTS_DIR}\nSaved scripts:\n${formatList(entries)}`;
          }
          ({ packages, nixPackages } = parseHeader(source));
          label = `${name}.py`;
        }

        let env;
        try {
          env = await buildEnv(packages, nixPackages);
        } catch (e) {
          // Surface the Nix error verbatim: "attribute missing" names the
          // bad package, which is exactly what the agent needs to fix.
          return `Error: nix environment build failed:\n${e.stderr || e.message}`;
        }

        const timeoutMs = Math.min(Number(args.timeout) || 120, 3600) * 1000;
        const scriptArgs = (args.args || []).map(String);
        const cmdline = `$ python3 ${label}${scriptArgs.length ? " " + scriptArgs.join(" ") : ""}`;

        try {
          const { stdout, stderr } = await run(
            `${env}/bin/python3`,
            [scriptPath, ...scriptArgs],
            {
              cwd: context.directory,
              timeout: timeoutMs,
              maxBuffer: 10 * 1024 * 1024,
              env: { ...process.env, PATH: `${env}/bin:${process.env.PATH}` },
            }
          );
          const out = (stdout || "") + (stderr ? `\n[stderr]\n${stderr}` : "");
          return `${savedMsg}${cmdline}\n${clip(out.trim() || "(no output)")}`;
        } catch (e) {
          if (e.killed) {
            return `${savedMsg}${cmdline}\nError: timed out after ${timeoutMs / 1000}s`;
          }
          const out = (e.stdout || "") + (e.stderr ? `\n[stderr]\n${e.stderr}` : "");
          return `${savedMsg}${cmdline} (exit ${e.code ?? "?"})\n${clip(out.trim() || "(no output)")}`;
        }
      },
    },
  },
  };
};

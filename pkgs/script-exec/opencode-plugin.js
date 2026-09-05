// OpenCode plugin for script-exec.
// One tool, script_exec: run a Python script with dependencies resolved via
// Nix (python3.withPackages + extra nixpkgs tools on PATH), inside the jail.
//
// Three usage shapes:
//   script only          -- throwaway: temp file, run, discard
//   script + name        -- save to ~/scratch/scripts/<name>.py, then run
//   name only            -- re-run a saved script; deps come from its header
//
// Saved scripts are self-contained: dependency metadata lives in a header
// block inside the file itself, so a script re-read later (or hand-edited
// with the Edit tool) carries its own deps -- no sidecar state, no lossy
// round-trip. The header is the single source of truth on re-run.
//
//   # /// script-exec
//   # packages = ["requests"]
//   # nixPackages = ["ffmpeg"]
//   # ///
//
// Deliberately NOT real PEP 723 ("# /// script"): that format declares PyPI
// requirements for uv-style runners, and these are nixpkgs attribute names.
// Claiming the PEP 723 marker with nix attrs would confuse any tool that
// actually speaks it.

import { createRequire } from "node:module";
import { execFile } from "node:child_process";
import { mkdir, readFile, writeFile, rm } from "node:fs/promises";
import { tmpdir, homedir } from "node:os";
import { join } from "node:path";
import { promisify } from "node:util";

const require = createRequire(
  (process.env.HOME || "/root") + "/.config/opencode/package.json"
);
const { z } = require("zod");
const run = promisify(execFile);

const SCRIPTS_DIR = join(homedir(), "scratch", "scripts");
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

export function makeHeader(packages, nixPackages) {
  // Both lines always present, even when empty: the metadata must be
  // retrievable from the file alone, not reconstructed from absence.
  return [
    HEADER_START,
    `# packages = ${JSON.stringify(packages)}`,
    `# nixPackages = ${JSON.stringify(nixPackages)}`,
    HEADER_END,
  ].join("\n");
}

export function parseHeader(source) {
  const lines = source.split("\n");
  const start = lines.indexOf(HEADER_START);
  if (start === -1) return { packages: [], nixPackages: [] };
  const out = { packages: [], nixPackages: [] };
  for (let i = start + 1; i < lines.length; i++) {
    if (lines[i].trim() === HEADER_END) break;
    const m = lines[i].match(/^#\s*(packages|nixPackages)\s*=\s*(\[.*\])\s*$/);
    if (!m) continue;
    try {
      const arr = JSON.parse(m[2]);
      if (Array.isArray(arr)) out[m[1]] = arr.map(String);
    } catch {
      // malformed line: ignored, stays empty -- the run will then fail on a
      // missing import, which points straight back at the header
    }
  }
  return out;
}

export function stripHeader(source) {
  const lines = source.split("\n");
  const start = lines.indexOf(HEADER_START);
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
export function withHeader(body, packages, nixPackages) {
  const stripped = stripHeader(body);
  const header = makeHeader(packages, nixPackages);
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

export default async (_ctx) => ({
  tool: {
    script_exec: {
      description:
        "Run a Python script with dependencies resolved via Nix. Declare " +
        "python packages (nixpkgs python3Packages attribute names, e.g. " +
        "'requests', 'numpy', 'beautifulsoup4') and extra system tools " +
        "(top-level nixpkgs attrs, e.g. 'ffmpeg') and they are provided " +
        "automatically -- no pip, no venv. Pass `script` alone for a " +
        "throwaway run; add `name` to save it to ~/scratch/scripts/<name>.py " +
        "for later reuse (persists across sessions); pass `name` alone to " +
        "re-run a saved script, whose dependencies are read from the " +
        "'# /// script-exec' header inside the file. Saved scripts are " +
        "plain files: browse with ls, edit with Edit (including the header " +
        "to change deps), then re-run by name.",
      args: {
        script: z
          .string()
          .optional()
          .describe(
            "Full Python source. Omit to re-run a saved script by name."
          ),
        name: z
          .string()
          .optional()
          .describe(
            "Script name ([A-Za-z0-9_-]). With `script`: save (or overwrite) " +
              "then run. Alone: re-run the saved script."
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
      },
      async execute(args, context) {
        const script = args.script;
        let name = String(args.name || "").trim().replace(/\.py$/, "");
        if (name && !NAME_RE.test(name)) {
          return `Error: invalid name ${JSON.stringify(name)} (allowed: [A-Za-z0-9_-])`;
        }
        if (!script && !name) {
          return "Error: provide `script` (run code), `name` (re-run saved), or both (save then run)";
        }

        let packages = args.packages || [];
        let nixPackages = args.nixPackages || [];
        let scriptPath;
        let tempPath = null;
        let label;

        try {
          if (script) {
            if (name) {
              await mkdir(SCRIPTS_DIR, { recursive: true });
              scriptPath = join(SCRIPTS_DIR, `${name}.py`);
              await writeFile(
                scriptPath,
                withHeader(script, packages, nixPackages)
              );
              label = `${name}.py`;
            } else {
              tempPath = join(
                tmpdir(),
                `script-exec-${Date.now()}-${Math.random().toString(36).slice(2)}.py`
              );
              scriptPath = tempPath;
              await writeFile(scriptPath, script);
              label = "script.py";
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
              return `Error: no saved script ${name}.py in ${SCRIPTS_DIR}`;
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
          const saved =
            script && name
              ? `saved to ${scriptPath} (deps in its header; re-run with name only)\n`
              : "";

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
            const out =
              (stdout || "") +
              (stderr ? `\n[stderr]\n${stderr}` : "");
            return `${saved}${cmdline}\n${clip(out.trim() || "(no output)")}`;
          } catch (e) {
            if (e.killed) {
              return `${saved}${cmdline}\nError: timed out after ${timeoutMs / 1000}s`;
            }
            const out =
              (e.stdout || "") + (e.stderr ? `\n[stderr]\n${e.stderr}` : "");
            return `${saved}${cmdline} (exit ${e.code ?? "?"})\n${clip(out.trim() || "(no output)")}`;
          }
        } finally {
          if (tempPath) await rm(tempPath, { force: true });
        }
      },
    },
  },
});

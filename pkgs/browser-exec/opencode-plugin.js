// OpenCode plugin for browser-exec.
// One tool, browser_exec: evaluate JS against a Firefox instance running
// pkgs/browser-exec/bridge.uc.js, over the unix socket it listens on.
//
// Silhouette matches script-exec's opencode-plugin.js deliberately (same
// header format, same save/list/re-run shapes) but there is no `nix build`
// in the loop -- eval is a live socket round-trip, so it's fast enough to be
// genuinely ephemeral.
//
// Usage shapes:
//   script only          -- throwaway: evals against the bridge, nothing saved
//   script + name        -- save to the snippet library, then eval it
//   name only            -- re-eval a saved snippet
//   list: true/"substr"  -- list (optionally filter) saved snippets by header
//   reload: true         -- ask the bridge to re-scan the userscript library
//
// Saved snippets carry their own metadata (Tampermonkey-style is for
// *.user.js in the userscript library; this header is script-exec's own
// JSON-in-comment style, since these are eval snippets, not userscripts):
//
//   // /// browser-exec
//   // description = "One line: what it does"
//   // world = "chrome" | "page"
//   // ///
//
// The userscript library itself (~/.local/share/browser-exec/userscripts/)
// is not managed by this tool -- write *.user.js files there with the normal
// file tools, then call `reload`. Userscripts are files; this tool is eval
// and orchestration.

import { createRequire } from "node:module";
import { execFile } from "node:child_process";
import { mkdir, readFile, writeFile, readdir, stat, rm } from "node:fs/promises";
import { homedir } from "node:os";
import { join } from "node:path";
import net from "node:net";
import { promisify } from "node:util";

const run = promisify(execFile);

// Lazy, same reasoning as script-exec: zod resolves from opencode's own
// install, which only exists once this plugin loads inside the jail. Pure
// header functions below must import cleanly without it (see test.mjs).
function loadZod() {
  const require = createRequire(
    (process.env.HOME || "/root") + "/.config/opencode/package.json"
  );
  return require("zod").z;
}

const LIB_DIR = join(homedir(), ".local", "share", "browser-exec");
const SNIPPETS_DIR = join(LIB_DIR, "snippets");
const TEMP_DIR = join(SNIPPETS_DIR, ".temp");
const TEMP_KEEP = 20;
const SOCK_PATH =
  process.env.BROWSER_EXEC_SOCKET ||
  join(process.env.XDG_RUNTIME_DIR || "/tmp", "browser-exec", "bridge.sock");

const NAME_RE = /^[A-Za-z0-9_-]+$/;
const HEADER_START = "// /// browser-exec";
const HEADER_END = "// ///";
const OUTPUT_CAP = 15000; // lower than script-exec's 50k -- DOM dumps are the common failure mode

export function makeHeader(description, world) {
  return [
    HEADER_START,
    `// description = ${JSON.stringify(description || "")}`,
    `// world = ${JSON.stringify(world || "chrome")}`,
    HEADER_END,
  ].join("\n");
}

export function parseHeader(source) {
  const lines = source.split("\n");
  const start = lines.findIndex((l) => l.trim() === HEADER_START);
  const out = { description: "", world: "chrome" };
  if (start === -1) return out;
  for (let i = start + 1; i < lines.length; i++) {
    if (lines[i].trim() === HEADER_END) break;
    const mDesc = lines[i].match(/^\/\/\s*description\s*=\s*("(?:[^"\\]|\\.)*")\s*$/);
    if (mDesc) {
      try {
        out.description = JSON.parse(mDesc[1]);
      } catch {
        // malformed: stays ""
      }
      continue;
    }
    const mWorld = lines[i].match(/^\/\/\s*world\s*=\s*("(?:[^"\\]|\\.)*")\s*$/);
    if (mWorld) {
      try {
        const w = JSON.parse(mWorld[1]);
        if (w === "chrome" || w === "page") out.world = w;
      } catch {
        // malformed: stays "chrome"
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

export function withHeader(body, description, world) {
  const header = makeHeader(description, world);
  return `${header}\n${stripHeader(body)}`;
}

function clip(s) {
  if (s.length <= OUTPUT_CAP) return s;
  return s.slice(0, OUTPUT_CAP) + `\n... (output truncated at ${OUTPUT_CAP} chars)`;
}

// One base64-encoded JS body per connection, newline-terminated; reply is one
// line of JSON then EOF. See pkgs/browser-exec/bridge.uc.js for the server
// side of this protocol.
function evalOverBridge(source, timeoutMs) {
  return new Promise((resolve, reject) => {
    const sock = net.createConnection(SOCK_PATH);
    let buf = "";
    let settled = false;
    const done = (fn, arg) => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      sock.destroy();
      fn(arg);
    };
    const timer = setTimeout(() => {
      done(reject, new Error(`bridge eval timed out after ${timeoutMs}ms`));
    }, timeoutMs);
    sock.on("connect", () => {
      // write() only, never end() -- on a unix socket, bun's net.Socket
      // (opencode's tools run under bun, not node) drops or corrupts the
      // pending write the moment end() is called on the same socket, even
      // from a write() callback confirming the flush already completed.
      // Confirmed empirically: sock.end(data), and write()+end() as two
      // calls, both reproduce the client reading a clean close with zero
      // bytes. The bridge doesn't need the client's EOF anyway -- it reads
      // up to the first newline and responds by closing its own end (see
      // bridge.uc.js), which is what actually terminates this connection.
      sock.write(Buffer.from(source).toString("base64") + "\n");
    });
    sock.on("data", (chunk) => {
      buf += chunk.toString("utf8");
    });
    sock.on("close", () => done(resolve, buf));
    sock.on("error", (e) => {
      if (e.code === "ENOENT" || e.code === "ECONNREFUSED") {
        done(
          reject,
          new Error(
            `no bridge listening at ${SOCK_PATH} -- is firefox-neo running with browser-exec's bridge.uc.js loaded?`
          )
        );
        return;
      }
      done(reject, e);
    });
  });
}

async function ensureRepo() {
  await mkdir(SNIPPETS_DIR, { recursive: true });
  try {
    await stat(join(SNIPPETS_DIR, ".git"));
  } catch {
    await run("git", ["init", "-q"], { cwd: SNIPPETS_DIR });
    await writeFile(join(SNIPPETS_DIR, ".gitignore"), ".temp/\n");
  }
}

async function commit(message) {
  try {
    await run("git", ["add", "-A", "--", ":!.temp"], { cwd: SNIPPETS_DIR });
    await run("git", ["commit", "-q", "-m", message, "--allow-empty-message"], {
      cwd: SNIPPETS_DIR,
    });
  } catch {
    // e.g. nothing to commit -- fine
  }
}

async function listSaved(filter) {
  let files;
  try {
    files = (await readdir(SNIPPETS_DIR)).filter((f) => f.endsWith(".js"));
  } catch {
    return [];
  }
  const needle = typeof filter === "string" ? filter.toLowerCase() : null;
  const out = [];
  for (const f of files) {
    const name = f.slice(0, -3);
    let description = "";
    let world = "chrome";
    try {
      ({ description, world } = parseHeader(await readFile(join(SNIPPETS_DIR, f), "utf8")));
    } catch {
      continue;
    }
    if (needle && !name.toLowerCase().includes(needle) && !description.toLowerCase().includes(needle)) {
      continue;
    }
    out.push({ name, description, world });
  }
  out.sort((a, b) => a.name.localeCompare(b.name));
  return out;
}

function formatList(entries) {
  if (!entries.length) return "(no saved snippets match)";
  return entries
    .map((e) => `${e.name} [${e.world}] -- ${e.description || "(no description)"}`)
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

// Wraps a snippet body so it can call the bridge's pageEval() from a chrome-
// world script -- `world: "page"` snippets are just `return pageEval(\`...\`)`
// under the hood, but that indirection would be tedious to write by hand for
// every request, so the tool does it based on the header/arg instead.
function wrapForWorld(body, world) {
  if (world === "page") {
    // Backtick-embed: escape backtick/backslash/${ so the body can't break
    // out of the template literal it's wrapped in.
    const escaped = body.replace(/\\/g, "\\\\").replace(/`/g, "\\`").replace(/\$\{/g, "\\${");
    return `return await pageEval(\`${escaped}\`);`;
  }
  return body;
}

export default async (_ctx) => {
  const z = loadZod();
  return {
  tool: {
    browser_exec: {
      description:
        "What: evaluate JavaScript against a running Firefox (firefox-neo), " +
        "either chrome-privileged (`world: 'chrome'`, default -- full browser " +
        "UI/XPCOM access, sandbox helpers: tabs(), openTab(url), $/$$, cs(), R(), " +
        "readable(), contentEval(), pageEval(), reloadUserscripts()) or scoped " +
        "to the active tab's page (`world: 'page'` -- runs in that page's own " +
        "content window). " +
        "When: extracting structure/text from a page, driving the browser UI, " +
        "or iterating on a userscript before saving it. Requires firefox-neo " +
        "running with browser-exec's bridge.uc.js loaded (unix socket, no " +
        "auth beyond filesystem permissions -- see pkgs/browser-exec). " +
        "Before writing a new snippet, call with `list` to check for an " +
        "existing one. " +
        "Shapes: `script` alone evals once, nothing saved; `script`+`name`" +
        "(+`description`) saves to the snippet library and evals it, git-" +
        "committed; `name` alone re-evals a saved snippet; `list` (true, or " +
        "a substring) returns saved snippets without evaluating anything; " +
        "`reload: true` asks the bridge to re-scan the userscript library " +
        "(~/.local/share/browser-exec/userscripts/*.user.js) after you've " +
        "written or edited one with the normal file tools.",
      args: {
        script: z
          .string()
          .optional()
          .describe(
            "JS body; bare `await`/`return` work. Omit to re-run a saved " +
              "snippet by name, reload, or list."
          ),
        world: z
          .enum(["chrome", "page"])
          .optional()
          .describe("'chrome' (default) or 'page' (active tab's content window)."),
        name: z
          .string()
          .optional()
          .describe(
            "Snippet name ([A-Za-z0-9_-]). With `script`: save (or update, " +
              "git-committed) then eval. Alone: re-eval the saved snippet."
          ),
        description: z
          .string()
          .optional()
          .describe("One-line summary. Required the first time a `name` is saved."),
        message: z.string().optional().describe("Git commit message for this save."),
        timeout: z.number().optional().describe("Eval timeout in seconds (default 15)."),
        list: z
          .union([z.boolean(), z.string()])
          .optional()
          .describe(
            "List saved snippets instead of evaluating anything. `true` " +
              "lists all; a string filters by substring."
          ),
        reload: z
          .boolean()
          .optional()
          .describe("Ask the bridge to re-scan the userscript library."),
      },
      async execute(args) {
          if (args.reload) {
            try {
              const out = await evalOverBridge("return await reloadUserscripts();", 15000);
              return `reload: ${out.trim()}`;
            } catch (e) {
              return `Error: ${e.message}`;
            }
          }

          if (args.list) {
            const entries = await listSaved(typeof args.list === "string" ? args.list : null);
            return formatList(entries);
          }

          const script = args.script;
          let name = String(args.name || "").trim().replace(/\.js$/, "");
          if (name && !NAME_RE.test(name)) {
            return `Error: invalid name ${JSON.stringify(name)} (allowed: [A-Za-z0-9_-])`;
          }
          if (!script && !name) {
            return "Error: provide `script` (eval), `name` (re-eval saved), `list`, or `reload`";
          }

          let world = args.world === "page" ? "page" : "chrome";
          let body;
          let label;
          let savedMsg = "";

          if (script) {
            if (name) {
              await ensureRepo();
              const snippetPath = join(SNIPPETS_DIR, `${name}.js`);
              let existingDescription = "";
              let isUpdate = false;
              try {
                ({ description: existingDescription } = parseHeader(
                  await readFile(snippetPath, "utf8")
                ));
                isUpdate = true;
              } catch {
                // new snippet
              }
              const description = args.description || existingDescription;
              if (!description) {
                return "Error: `description` is required the first time a snippet is saved";
              }
              await writeFile(snippetPath, withHeader(script, description, world));
              const commitMsg = args.message || (isUpdate ? `update ${name}` : `add ${name}`);
              await commit(commitMsg);
              label = `${name}.js`;
              savedMsg = `saved to ${snippetPath} (${commitMsg}); re-run with name only\n`;
            } else {
              await mkdir(TEMP_DIR, { recursive: true });
              const tempName = `${Date.now()}-${Math.random().toString(36).slice(2)}`;
              await writeFile(
                join(TEMP_DIR, `${tempName}.js`),
                withHeader(script, args.description || "", world)
              );
              await pruneTemp();
              label = `${tempName}.js`;
            }
            body = script;
          } else {
            const snippetPath = join(SNIPPETS_DIR, `${name}.js`);
            let source;
            try {
              source = await readFile(snippetPath, "utf8");
            } catch {
              const entries = await listSaved(null);
              return `Error: no saved snippet ${name}.js in ${SNIPPETS_DIR}\nSaved snippets:\n${formatList(entries)}`;
            }
            ({ world } = parseHeader(source));
            body = stripHeader(source);
            label = `${name}.js`;
          }

          const timeoutMs = Math.min(Number(args.timeout) || 15, 120) * 1000;
          try {
            const out = await evalOverBridge(wrapForWorld(body, world), timeoutMs);
            return `${savedMsg}$ browser_exec [${world}] ${label}\n${clip(out.trim() || "(no output)")}`;
          } catch (e) {
            return `${savedMsg}$ browser_exec [${world}] ${label}\nError: ${e.message}`;
          }
        },
      },
    },
  };
};

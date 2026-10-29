// OpenCode plugin for browser-exec.
// One tool, browser_exec: evaluate JS against a Firefox instance running
// pkgs/browser-exec/bridge.sys.mjs, over the unix socket it listens on.
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

// The bridge replies {ok, value | error, stack?, note?}. Render it for a
// reader instead of echoing the envelope: a string value prints raw (real
// newlines, not "\n" escapes inside a JSON string), anything else as
// indented JSON; errors print as "Error: ..." so they can't be mistaken for
// a result.
export function renderReply(raw) {
  let r;
  try {
    r = JSON.parse(raw);
  } catch {
    return raw.trim() || "(no output)";
  }
  if (!r || typeof r !== "object" || !("ok" in r)) return raw.trim();
  if (!r.ok) return `Error: ${r.error}${r.stack ? `\n${r.stack}` : ""}`;
  const v = r.value;
  const body = typeof v === "string" ? v : JSON.stringify(v, null, 2);
  return r.note ? `${body}\n(${r.note})` : body;
}

// One base64-encoded JS body per connection, newline-terminated; reply is one
// line of JSON then EOF. See pkgs/browser-exec/bridge.sys.mjs for the server
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
      // bridge.sys.mjs), which is what actually terminates this connection.
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
            `no bridge listening at ${SOCK_PATH} -- is firefox-neo running with browser-exec's bridge.sys.mjs loaded?`
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
// world script -- `world: "page"` snippets are just `return pageEval(...)`
// under the hood, but that indirection would be tedious to write by hand for
// every request, so the tool does it based on the header/arg instead.
//
// The body travels as a JSON string literal: no template-literal escaping to
// get wrong. `tab` (URL prefix, or a numeric tab id) pins the target tab, so
// a page-world call doesn't silently hit whatever the user has focused.
//
// The bridge's own content-probe timeout is passed explicitly and set below
// this tool's socket timeout. Otherwise the bridge's 8s default silently caps
// every page-world snippet: ask for `timeout: 60`, wait 8s, get "page eval
// timed out" and go looking for the bug in the page.
export function wrapForWorld(body, world, timeoutMs, tab) {
  if (world === "page") {
    const budget = Math.max(1000, Math.floor((timeoutMs || 15000) * 0.9));
    const target =
      tab == null || tab === "" ? "null" : /^\d+$/.test(String(tab)) ? `{tab:${Number(tab)}}` : JSON.stringify(String(tab));
    return `return await pageEval(${JSON.stringify(body)}, ${target}, ${budget});`;
  }
  return body;
}

// ---- reuse check ----
//
// Agents kept rewriting `document.body.innerText.slice(...)` and one-off URL
// builders instead of re-running or extending a saved snippet, despite the
// "list first" instruction. So each unsaved script (and each new name) gets
// one Jev request against the library before it runs: an exact match blocks,
// a near match or a repeat of a recent throwaway gets a one-line nudge.
const JEV_ENDPOINT = "https://api.typesafe.ai/v1/systemone";
const JEV_TIMEOUT_MS = 3000;
const BLOCK_MIN_P = 0.8;
const NOTE_MIN_P = 0.6;
const RECENT_INTENTS = 20;
// Bridge helpers are not snippets, but "read the page text" should land on
// readable() rather than a fourth innerText one-liner.
const BUILTINS = {
  "readable()": "built-in helper: readable(target?) returns the page's main text content",
  "openTab()": "built-in helper: openTab(url, {selector?}) opens a tab and waits for it to load",
  "jev.observe()": "built-in helper: jev.observe() returns a page snapshot {url, title, text, actions}",
};
const VERDICTS = {
  reuse: "an existing snippet or helper in `library` already does what `intent` describes",
  extend: "an existing snippet does nearly this; it should gain a parameter or helper instead of a new script",
  save: "not in the library, but likely to be needed again (e.g. `recent_intents` already did the same thing)",
  throwaway: "a one-off probe specific to this moment, not worth saving",
};

export function buildClassifyRequest({ intent, script, url, snippets, recent }) {
  const library = Object.fromEntries(snippets.map((s) => [s.name, s.description || "(no description)"]));
  const candidates = { ...library, ...BUILTINS, none: "nothing in the library does this" };
  return {
    state: {
      intent,
      script: script.length > 2000 ? script.slice(0, 2000) + "\n…" : script,
      ...(url ? { tab: url } : {}),
      library: { ...library, ...BUILTINS },
      recent_intents: recent,
    },
    questions: {
      match: {
        type: "choice",
        instructions: "Which `library` entry is closest to doing what `intent` (implemented by `script`) describes?",
        criteria: candidates,
      },
      verdict: { type: "choice", instructions: "How should this script be handled?", criteria: VERDICTS },
    },
  };
}

// Jev answers -> {block?: string, note?: string} or null (nothing to say).
// `saving`: the call saves a new name, so never block, only flag a duplicate.
export function readVerdict(answers, { force = false, saving = false } = {}) {
  const verdict = answers?.verdict?.choice;
  const p = answers?.verdict?.probabilities?.[verdict] ?? 0;
  const match = answers?.match?.choice;
  const hit = match && match !== "none" ? match : null;
  if (!verdict || p < NOTE_MIN_P) return null;
  const isBuiltin = hit && hit in BUILTINS;
  const how = isBuiltin ? `call ${hit} inside a script` : `run name:${JSON.stringify(hit)}`;
  if (verdict === "reuse" && hit) {
    if (saving) return { note: `[browser-exec] looks like a duplicate of ${hit}; consider extending that instead` };
    if (!force && p >= BLOCK_MIN_P)
      return { block: `[browser-exec] not run: ${hit} already does this -- ${how}, or pass force:true if it really doesn't` };
    return { note: `[browser-exec] ${hit} may already do this -- ${how}` };
  }
  if (verdict === "extend" && hit && !isBuiltin)
    return { note: `[browser-exec] close to ${hit}: extend that snippet and save it under its name rather than a new one` };
  if (verdict === "save" && !saving)
    return { note: "[browser-exec] looks repeatable: save it with name+description so the next session can re-run it" };
  return null;
}

async function jevKey() {
  return process.env.TYPESAFE_API_KEY?.trim() || (await readFile("/run/secrets/jev/api-key", "utf8")).trim();
}

async function recentIntents() {
  const files = await readdir(TEMP_DIR).catch(() => []);
  const rows = await Promise.all(
    files.map(async (f) => {
      const p = join(TEMP_DIR, f);
      const [s, src] = await Promise.all([stat(p).catch(() => null), readFile(p, "utf8").catch(() => "")]);
      return { mtime: s?.mtimeMs ?? 0, intent: parseHeader(src).description };
    })
  );
  return rows
    .filter((r) => r.intent)
    .sort((a, b) => b.mtime - a.mtime)
    .slice(0, RECENT_INTENTS)
    .map((r) => r.intent);
}

// Any failure (no key, offline, slow) -> null: the call runs as if unchecked.
async function classify(input, opts) {
  try {
    const { state, questions } = buildClassifyRequest({
      ...input,
      snippets: await listSaved(null),
      recent: await recentIntents(),
    });
    const res = await fetch(JEV_ENDPOINT, {
      method: "POST",
      headers: { Authorization: `Bearer ${await jevKey()}`, "Content-Type": "application/json" },
      body: JSON.stringify({ model: "jev-latest", state, questions }),
      signal: AbortSignal.timeout(JEV_TIMEOUT_MS),
    });
    if (!res.ok) return null;
    return readVerdict((await res.json()).answers, opts);
  } catch {
    return null;
  }
}

// V1 plugin shape (`export default { id, server }`): with a bare-function
// default, opencode's legacy loader calls every named export as a plugin,
// and one throwing helper (buildClassifyRequest on opencode's ctx) aborted
// the whole file. See axiom-ledger's plugin for the same fix.
async function server(_ctx) {
  const z = loadZod();
  return {
  tool: {
    browser_exec: {
      description:
        "Check the snippet library (`list: true`) before writing a new " +
        "`script`: re-running a saved snippet by `name` beats rewriting it. " +
        "An unsaved `script` needs a one-line `intent`; it is checked " +
        "against the library first, and is NOT run when a saved snippet " +
        "already does it (the result names it; `force: true` overrides). " +
        "Near matches and repeatable scripts get a one-line hint to extend " +
        "or save instead. " +
        "What: evaluate JavaScript against a running Firefox (firefox-neo), " +
        "either chrome-privileged (`world: 'chrome'`, default -- full browser " +
        "UI/XPCOM access) or in a tab's page (`world: 'page'` -- the page's " +
        "own JS environment, no Xrays: spreading NodeLists, page globals and " +
        "frameworks all work like the devtools console). Pin the tab with " +
        "`tab` (URL prefix or tab id); without it, page code runs in whatever " +
        "tab the user has focused. " +
        "Chrome-world helpers: `tabs()` -> [{tab, window, url, title, " +
        "selected, ...}] (each row is a valid target); `await openTab(url, " +
        "{selector?, select?, wait?})` opens a tab, waits for load (or the " +
        "selector), returns its target; `selectTab(target)`, " +
        "`closeTab(target)`; `await waitFor(target, {selector?, timeout?})`; " +
        "`await pageEval(code, target?, timeoutMs?)` runs page-world code in " +
        "that tab (code is a string; `return` optional); `readable(target?)`; " +
        "`sidebarEval(code)` targets the Sidebery sidebar, NOT a page; " +
        "`sleep(ms)`; $/$$/cs()/R() on chrome DOM; reloadUserscripts(); jev; " +
        "snippet(name). A target is a tab id ({tab: n}), a URL prefix string " +
        "or RegExp, or a window id. " +
        "When: extracting structure/text from a page, filling forms, driving " +
        "the browser UI, or iterating on a userscript before saving it. " +
        "Requires firefox-neo running with browser-exec's bridge.sys.mjs " +
        "loaded (unix socket, no auth beyond filesystem permissions -- see " +
        "pkgs/browser-exec). " +
        "Shapes: `list` (true, or a substring) returns saved snippets without " +
        "evaluating anything -- do this first; `script` alone evals once, " +
        "nothing saved; `script`+`name`(+`description`) saves to the snippet " +
        "library and evals it, git-committed; `name` alone re-evals a saved " +
        "snippet; `reload: true` asks the bridge to re-scan the userscript " +
        "library (~/.local/share/browser-exec/userscripts/*.user.js) after " +
        "you've written or edited one with the normal file tools. " +
        "JEV (chrome world): `jev` is TypeSafe's Jev, a fast decision model " +
        "that answers typed questions about a JSON state -- it never writes " +
        "text or code, so you write the script and it makes the calls inside " +
        "it. `await jev.noul(state, 'Is there a captcha?')` -> 0..1; " +
        "`jev.choose(state, instr, ['a','b'] | {a:'desc'})` -> {choice, " +
        "probabilities, confidence}; `jev.score(state, instr, [levels])` -> " +
        "{score, confidence}; `jev.ask(state, {id: {type, instructions, " +
        "criteria}})` batches many questions in one ~fast call (prefer this). " +
        "`jev.observe()` -> page snapshot {url,title,text,actions}; " +
        "`jev.run({goal, values:[strings it may type], ops:{NAME:{description, " +
        "run: page => ...}}, maxSteps, minConfidence})` is a browser agent loop " +
        "(CLICK/TYPE_TEXT/SELECT/SCROLL/WAIT/DONE/BLOCKED + your ops) on the " +
        "active tab, returning {status, history}. `snippet(name)` runs a saved " +
        "snippet, e.g. as an op's run. Userscripts get jev.ask/noul/choose/" +
        "score with `// @grant jev` in their header.",
      args: {
        script: z
          .string()
          .optional()
          .describe(
            "JS body. `return` is optional: a lone expression (e.g. " +
              "`document.title`) returns its value; a multi-statement body " +
              "needs `return`. Bare `await` works. In `world: 'page'` the " +
              "body runs in the page's own window (document, location, " +
              "fetch, page globals). Omit to re-run a saved snippet by name, " +
              "reload, or list."
          ),
        world: z
          .enum(["chrome", "page"])
          .optional()
          .describe("'chrome' (default) or 'page' (a tab's content window; see `tab`)."),
        tab: z
          .union([z.string(), z.number()])
          .optional()
          .describe(
            "world 'page' only: which tab -- a URL prefix (e.g. " +
              "'https://www.kingston.com/en/support/rma') or a tab id from " +
              "tabs(). Default: the focused tab, which the user may change " +
              "under you."
          ),
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
        intent: z
          .string()
          .optional()
          .describe(
            "Required with an unsaved `script`: one line on what it is for (e.g. " +
              "'read visible log rows on Datadog'). Checked against saved snippets."
          ),
        force: z
          .boolean()
          .optional()
          .describe("Run an unsaved `script` even though a saved snippet was judged to do the same."),
        timeout: z
          .number()
          .optional()
          .describe(
            "Eval timeout in seconds (default 15). For `world: 'page'` the " +
              "bridge's content probe is budgeted just under this, so a " +
              "slow page-world snippet gets the time you asked for."
          ),
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
            return `reload: ${renderReply(out)}`;
            } catch (e) {
              return `Error: ${e.message}`;
            }
          }

          // Tool-call args can arrive with the boolean stringified ("true").
          if (args.list && args.list !== "false") {
            const entries = await listSaved(typeof args.list === "string" && args.list !== "true" ? args.list : null);
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
          const intent = String(args.intent || "").trim();
          if (script && !name && !intent) {
            return "Error: `intent` is required for an unsaved script (one line: what it is for)";
          }
          const force = args.force === true || args.force === "true";
          const tabUrl = typeof args.tab === "string" ? args.tab : undefined;

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
              const check = isUpdate
                ? null
                : await classify({ intent: intent || description, script, url: tabUrl }, { saving: true });
              await writeFile(snippetPath, withHeader(script, description, world));
              const commitMsg = args.message || (isUpdate ? `update ${name}` : `add ${name}`);
              await commit(commitMsg);
              label = `${name}.js`;
              savedMsg = `${check?.note ? check.note + "\n" : ""}saved to ${snippetPath} (${commitMsg}); re-run with name only\n`;
            } else {
              const check = await classify({ intent, script, url: tabUrl }, { force });
              if (check?.block) return check.block;
              if (check?.note) savedMsg = check.note + "\n";
              await mkdir(TEMP_DIR, { recursive: true });
              const tempName = `${Date.now()}-${Math.random().toString(36).slice(2)}`;
              await writeFile(
                join(TEMP_DIR, `${tempName}.js`),
                withHeader(script, intent, world)
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
            const out = await evalOverBridge(wrapForWorld(body, world, timeoutMs, args.tab), timeoutMs);
            return `${savedMsg}$ browser_exec [${world}] ${label}\n${clip(renderReply(out))}`;
          } catch (e) {
            return `${savedMsg}$ browser_exec [${world}] ${label}\nError: ${e.message}`;
          }
        },
      },
    },
  };
}

export default { id: "browser-exec", server };

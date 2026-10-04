// OpenCode plugin: jev_review + jev_probe -- an inspection engine the calling
// agent steers, with a library of code probes Jev routes to.
//
// Jev (TypeSafe's System One model) never writes text; it answers typed
// questions (choice / noul / score) fast and cheap. The calling LLM plans.
// Probes sit between them: small JS modules (the agent writes and saves
// them with jev_probe) that check one kind of problem on one code unit,
// using deterministic code (regex gates, binaries via r.run, other probes via
// r.probe) and Jev questions. Jev never calls tools itself; it routes:
//
//   git diff (repo picked by `path`)       -> changed lines per file
//   ast-grep (tree-sitter) over the repo    -> code units with a kind (fn/impl/type/class/const/mod)
//   innermost unit per changed line         -> units under review; test units skipped
//   same-kind token similarity              -> 2 nearest existing units, context in every state
//   per unit: probe whitelist (langs/kinds) -> gates (deterministic)
//             -> ONE Jev request: "is <probe description> plausible here?" per probe + agent questions
//             -> run the routed probes (recursion via r.probe, depth <= 3, shared call budget)
//   ranked lines, worst first
//
// Every Jev answer is cached per (state, question) for the life of the
// process, so follow-up passes only pay for new questions.
//
// Key: $TYPESAFE_API_KEY (the jail injects it), else /run/secrets/jev/api-key.

import { execFile } from "node:child_process";
import { createHash } from "node:crypto";
import { mkdir, mkdtemp, readdir, readFile, stat, writeFile } from "node:fs/promises";
import { createRequire } from "node:module";
import { homedir, tmpdir } from "node:os";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const ENDPOINT = "https://api.typesafe.ai/v1/systemone";
// Both substituted with store paths at build time (default.nix).
const AST_GREP = "@astGrep@".startsWith("@") ? "ast-grep" : "@astGrep@";
const SHIPPED_PROBES = "@probesDir@".startsWith("@") ? fileURLToPath(new URL("./probes", import.meta.url)) : "@probesDir@";
// Binaries shipped probes rely on, pinned at build time so r.run works
// whatever the jail's PATH holds. Anything else resolves via PATH.
const TOOLS = { "ast-grep": AST_GREP, rg: "@rg@".startsWith("@") ? "rg" : "@rg@" };
const USER_PROBES = path.join(homedir(), "scratch", "jev-probes");

const CONCURRENCY = 8; // Jev requests in flight
const MAX_UNITS = 200; // units per call
const MAX_CALLS = 500; // default Jev request budget per call, shared by all probes
const MAX_DEPTH = 3; // r.probe() nesting
const PROBE_TIMEOUT = 60_000;
const ROUTE_MIN = 0.35; // routing noul needed to run a CODE probe (declarative ones are asked directly); low: a missed finding costs more than a probe run
const MAX_POOL = 20000; // ponytail: neighbour candidates; a smarter index if repos outgrow it
const MAX_UNIT_LINES = 400; // longer units keep the changed region + exit lines (override: max_lines)
const FOLD_LINES = 60; // a changed container this small is reviewed whole, children folded in
const NEIGHBOUR_LINES = 80;
const NEIGHBOURS = 2;
const MIN_SIM = 0.25; // low on purpose: a restyled copy shares names more than shape; similarity is shown to Jev
const GRAM = 5;
const STOP_GRAM = 500; // shape n-grams shared by more units than this carry no signal

const LANGS = { ".rs": "rust", ".ts": "typescript", ".mts": "typescript", ".cts": "typescript", ".tsx": "typescript" };
const LANG_NAMES = { rust: "Rust", typescript: "TypeScript" };
const IE = "insufficient_evidence";
const NEGATIVE = new Set(["none", "ok", "consistent", "na", "n/a", "not_applicable", "no", "safe", "exact", "accurate", "guarded", "propagated"]);
const TEST_PATH = /(^|\/)(tests?|__tests__|benches)\/|[._](test|spec)\.[cm]?tsx?$/;
const TEST_ATTR = /^#\[(?:\w+::)*test\b|^#\[cfg\(test\)\]/;

const SCOPE =
  "Judge only the CHANGED lines of `unit` (prefixed '+'); unprefixed lines are context. " +
  "`neighbours` are the most similar existing units in the repo (with `similarity`, 0..1): context only, never under review.";

export const choice = (instructions, options) => ({
  type: "choice",
  instructions,
  criteria: { ...options, [IE]: "the code shown is too partial to judge" },
});

// One Jev choice answer -> { choice, abstain, p, labels }. p = total
// probability of the finding options (everything but the NEGATIVE ones,
// `ok_*` options and the abstention), `minor_*` options counted at half
// weight; labels = the top 2 findings at >= 0.1 (weighted).
const isNegative = (k) => NEGATIVE.has(k.toLowerCase()) || /^ok_/i.test(k);
const weight = (k) => (/^minor_/i.test(k) ? 0.5 : 1);
export function readAnswer(a, options) {
  const p = a?.probabilities;
  if (!p || !(a.choice in options)) throw new Error("malformed Jev answer");
  const findings = Object.entries(p)
    .filter(([k]) => k in options && k !== IE && !isNegative(k))
    .map(([k, v]) => [k, v * weight(k)])
    .sort((x, y) => y[1] - x[1]);
  return {
    choice: a.choice,
    abstain: a.choice === IE,
    p: findings.reduce((s, [, v]) => s + v, 0),
    labels: findings.filter(([, v]) => v >= 0.1).slice(0, 2),
    probabilities: p,
  };
}

// readAnswer result -> finding | null (nothing found) | { abstain }.
export function toFinding(a, extra = {}) {
  if (a.abstain) return { abstain: true };
  if (a.p < 0.1 || !a.labels.length) return null;
  const [[label], second] = a.labels;
  return { p: a.p, label, note: second ? `(also ${second[0]} ${second[1].toFixed(2)})` : undefined, ...extra };
}

// What a probe returned -> normalised result.
function normFinding(out) {
  if (!out) return { ok: true };
  if (out.abstain) return { abstain: true };
  const p = Math.min(1, Math.max(0, Number(out.p ?? 1)));
  return { p, label: String(out.label ?? "found"), note: out.note ? String(out.note) : undefined };
}

// Unified diff -> Map(file -> Set of added new-side line numbers), for
// supported languages only. Pure.
export function changedLines(diff) {
  const out = new Map();
  let file = null;
  let inHunk = false;
  let nl = 0;
  for (const line of diff.split("\n")) {
    if (line.startsWith("diff --git ")) {
      file = null;
      inHunk = false;
    } else if (!inHunk && line.startsWith("+++ ")) {
      const p = line.slice(4).replace(/^b\//, "");
      file = p !== "/dev/null" && LANGS[path.extname(p)] && !p.endsWith(".d.ts") ? p : null;
    } else if (line.startsWith("@@")) {
      inHunk = true;
      nl = Number(/^@@ -\d+(?:,\d+)? \+(\d+)/.exec(line)?.[1] ?? 0);
    } else if (file && inHunk && line[0] === "+") {
      if (!out.has(file)) out.set(file, new Set());
      out.get(file).add(nl++);
    } else if (inHunk && line[0] === " ") nl++;
  }
  return out;
}

// Files in the diff that get no units, so nobody mistakes "not reviewed" for
// "nothing to review": deleted, renamed without edits, removals only, and
// anything that isn't Rust/TS (Cargo.toml, package.json, …). Pure.
export function unreviewedFiles(diff) {
  const out = [];
  for (const block of diff.split(/^(?=diff --git )/m)) {
    const m = /^diff --git a\/(.+?) b\/(.+)$/m.exec(block);
    if (!m) continue;
    const [, a, b] = m;
    const body = block.split(/^@@/m).slice(1).join("\n").split("\n");
    const adds = body.some((l) => l[0] === "+");
    const dels = body.some((l) => l[0] === "-");
    const code = LANGS[path.extname(b)] && !b.endsWith(".d.ts");
    if (/^deleted file mode/m.test(block)) out.push(`deleted ${a}`);
    else if (/^rename from /m.test(block) && !adds) out.push(`renamed ${a}→${b}${dels ? " (lines removed)" : ""}`);
    else if (!code) out.push(b);
    else if (!adds && dels) out.push(`removals only: ${b}`);
  }
  return out;
}

// ast-grep rules, one per (language, unit kind); rule id "<lang>-<kind>".
const anyKind = (ks) => `{any: [${ks.map((k) => `{kind: ${k}}`).join(", ")}]}`;
const TOP = "{inside: {any: [{kind: program}, {kind: export_statement}]}}";
const FN_VALUE = "{has: {kind: variable_declarator, has: {field: value, any: [{kind: arrow_function}, {kind: function_expression}]}}}";
const TS_RULES = {
  fn: `{any: [{kind: function_declaration}, {kind: generator_function_declaration}, {kind: method_definition}, {all: [{kind: lexical_declaration}, ${TOP}, ${FN_VALUE}]}]}`,
  class: anyKind(["class_declaration", "abstract_class_declaration"]),
  type: anyKind(["interface_declaration", "type_alias_declaration", "enum_declaration"]),
  const: `{all: [{kind: lexical_declaration}, ${TOP}, {not: ${FN_VALUE}}]}`,
};
const RULES = [
  ...Object.entries({
    fn: ["function_item"],
    impl: ["impl_item"],
    type: ["struct_item", "enum_item", "trait_item", "type_item", "union_item"],
    mod: ["mod_item"],
  }).map(([k, ks]) => `id: rust-${k}\nlanguage: rust\nrule: ${anyKind(ks)}`),
  ...["typescript", "tsx"].flatMap((l) => Object.entries(TS_RULES).map(([k, r]) => `id: ${l}-${k}\nlanguage: ${l}\nrule: ${r}`)),
].join("\n---\n");

const run = (cmd, args, cwd, signal, timeout = 0) =>
  new Promise((resolve, reject) =>
    execFile(cmd, args, { cwd, signal, timeout, maxBuffer: 512 << 20 }, (err, stdout, stderr) =>
      err ? reject(new Error(String(stderr || err.message).trim())) : resolve(stdout)
    )
  );
const git = (cwd, args, signal) => run("git", args, cwd, signal);

// "pub fn foo(a: A) -> B {" -> "pub fn foo"; "impl X for Y {" -> "impl X for Y".
const unitName = (text) => text.split("\n")[0].split(/[({=]/)[0].trim().slice(0, 60);

// Every unit in the tree at `dir` (respects .gitignore).
export async function scanUnits(dir, signal) {
  const out = await run(AST_GREP, ["scan", "--inline-rules", RULES, "--json=stream", "."], dir, signal);
  return out
    .split("\n")
    .filter(Boolean)
    .flatMap((l) => {
      const m = JSON.parse(l);
      const file = m.file.replace(/^\.\//, "");
      const lang = LANGS[path.extname(file)];
      if (!lang || file.endsWith(".d.ts")) return [];
      const kind = m.ruleId.slice(m.ruleId.indexOf("-") + 1);
      return [{ file, lang, kind, start: m.range.start.line + 1, end: m.range.end.line + 1, text: m.text, name: unitName(m.text) }];
    });
}

const innermost = (units, file, line) => {
  let best = null;
  for (const u of units) {
    if (u.file === file && u.start <= line && line <= u.end && (!best || u.end - u.start < best.end - best.start)) best = u;
  }
  return best;
};

// Attribute lines directly above `start` (skipping comments/doc comments).
function attrsAbove(lines, start) {
  const out = [];
  for (let i = start - 2; i >= 0; i--) {
    const t = lines[i]?.trim() ?? "";
    if (t.startsWith("#[")) out.push(t);
    else if (!t.startsWith("//")) break;
  }
  return out;
}

// tree-sitter puts `#[...]` next to an item, not in it, so a struct's text
// starts at `pub struct` and Jev never sees its `#[derive(Debug)]`. Pull
// the attribute lines directly above (multi-line `#[derive(\n…\n)]` too)
// into the unit; `head` keeps the item's own first line. `lines`: the file.
export function withAttrs(u, lines) {
  if (u.lang !== "rust") return u;
  let start = u.start;
  for (let i = start - 2; i >= 0; ) {
    const t = lines[i].trim();
    if (t.startsWith("#[") && !t.startsWith("#![")) {
      start = i + 1;
      i--;
      continue;
    }
    // continuation of a multi-line attribute: find its `#[` within 20 lines
    if (!/\]$/.test(t)) break;
    let j = i - 1;
    while (j >= 0 && i - j < 20 && !lines[j].trim().startsWith("#[") && !/[;{}]$/.test(lines[j].trim())) j--;
    if (j < 0 || !lines[j].trim().startsWith("#[")) break;
    i = j;
  }
  return start === u.start ? u : { ...u, start, head: u.start, text: lines.slice(start - 1, u.start - 1).join("\n") + "\n" + u.text };
}

// Test code: test paths, #[test]-style attributes, or inside a #[cfg(test)] mod.
export function isTest(u, all, lines) {
  if (TEST_PATH.test(u.file)) return true;
  if (u.lang !== "rust" || !lines) return false;
  const own = (x) => lines.slice(x.start - 1, (x.head ?? x.start) - 1).map((t) => t.trim());
  const tagged = (x) => [...attrsAbove(lines, x.start), ...own(x)].some((a) => TEST_ATTR.test(a));
  return tagged(u) || all.some((m) => m.kind === "mod" && m.file === u.file && m.start < u.start && u.end <= m.end && tagged(m));
}

// Changed lines that are only imports/attributes/braces/comments aren't worth a call.
const TRIVIAL = /^\s*(use\s|import\s|export\s*\{|mod\s+\w+;|#!?\[|\/\/|[{}();,\]]*\s*$)/;
const CONTAINERS = new Set(["impl", "mod", "class"]);

// Changed lines -> units under review. Each line goes to its innermost unit;
// then containers (impl/class; mods never fold) are resolved:
//   * header changed and <= FOLD_LINES: reviewed whole as one unit (all
//     lines marked changed), its children dropped -- a new `impl Deref`
//     is judged as the impl, not as three fragments;
//   * otherwise the container is dropped when its own changed lines are only
//     header/braces/attributes (the children carry the change).
// Lines outside any unit become top-level pseudo-units (runs, gap <= 3),
// dropped when trivial. `fileLines` maps file -> its lines.
export function changedUnits(units, changed, fileLines) {
  const picked = new Map();
  let out = [];
  for (const [file, lines] of changed) {
    const orphans = [];
    for (const l of [...lines].sort((a, b) => a - b)) {
      const u = innermost(units, file, l);
      if (!u) {
        orphans.push(l);
        continue;
      }
      if (!picked.has(u)) {
        const c = { ...u, changed: new Set() };
        picked.set(u, c);
        out.push(c);
      }
      picked.get(u).changed.add(l);
    }
    const src = fileLines.get(file) ?? [];
    const runs = [];
    for (const l of orphans) {
      const last = runs[runs.length - 1];
      if (last && l - last[last.length - 1] <= 3) last.push(l);
      else runs.push([l]);
    }
    for (const r of runs) {
      if (r.every((l) => TRIVIAL.test(src[l - 1] ?? ""))) continue;
      const start = Math.max(1, r[0] - 2);
      const end = Math.min(src.length, r[r.length - 1] + 2);
      const text = src.slice(start - 1, end).join("\n");
      out.push({ file, lang: LANGS[path.extname(file)], kind: "top", start, end, text, name: "(top level)", changed: new Set(r) });
    }
  }

  // Containers, outermost first so a folded outer swallows inner ones. mods
  // never fold: a small `#[cfg(test)] mod tests` folded into one `mod` unit
  // that no probe's kinds accept, so its fns escaped review.
  const inside = (a, b) => a !== b && a.file === b.file && b.start <= a.start && a.end <= b.end;
  const conts = out.filter((u) => CONTAINERS.has(u.kind)).sort((a, b) => b.end - b.start - (a.end - a.start));
  const drop = new Set();
  for (const c of conts) {
    if (drop.has(c)) continue;
    const kids = out.filter((u) => inside(u, c));
    if (c.kind !== "mod" && c.changed.has(c.head ?? c.start) && c.end - c.start + 1 <= FOLD_LINES) {
      for (const k of kids) drop.add(k);
      c.changed = new Set(Array.from({ length: c.end - c.start + 1 }, (_, i) => c.start + i));
    } else if (kids.length) {
      const own = c.text.split("\n").filter((_, i) => c.changed.has(c.start + i));
      if (own.every((t) => TRIVIAL.test(t) || isHeader(t, c))) drop.add(c);
    }
  }
  out = out.filter((u) => !drop.has(u));
  for (const u of out) u.test = isTest(u, units, fileLines.get(u.file));
  return out;
}

// Is `t` the container's header line (`impl X for Y {`, `mod m {`, `class C {`)?
const isHeader = (t, c) => t.trim() === c.text.split("\n")[(c.head ?? c.start) - c.start].trim();

// `units` selectors -> units. "file:line" (also a pasted "file:12-48 fn x"
// label) picks the changed unit there, else the innermost unit even if
// unchanged (reviewed whole); explicit picks are never skipped as tests.
// Anything else is a path prefix over changed units. No selectors: all
// changed units. `skipTests` drops test units from the non-explicit picks.
export function selectUnits(all, changed, selectors, skipTests = true) {
  const keep = (u) => !(skipTests && u.test);
  if (!selectors?.length) return { units: changed.filter(keep), unmatched: [] };
  const units = new Set();
  const unmatched = [];
  for (const s of selectors) {
    const m = /^(\S+?):(\d+)/.exec(s);
    let hits;
    if (m) {
      const l = Number(m[2]);
      const c = changed.filter((u) => u.file === m[1] && u.start <= l && l <= u.end);
      const best = c.sort((a, b) => a.end - a.start - (b.end - b.start))[0];
      const any = !best && innermost(all, m[1], l);
      hits = best ? [best] : any ? [{ ...any, changed: null }] : [];
    } else hits = changed.filter((u) => u.file.startsWith(s) && keep(u));
    if (!hits.length) unmatched.push(s);
    for (const h of hits) units.add(h);
  }
  return { units: [...units], unmatched };
}

const KEYWORDS = new Set(
  (
    "as async await break const continue crate dyn else enum extern false fn for if impl in let loop match mod move mut pub " +
    "ref return self Self static struct super trait true type unsafe use where while abstract any boolean case catch class " +
    "constructor declare default delete do export extends finally function get implements import instanceof interface keyof " +
    "new null number of private protected public readonly set string switch this throw try typeof undefined var void yield"
  ).split(" ")
);
const TOKEN = /[A-Za-z_$][\w$]*|\d[\w.]*|"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\\n])*'|`(?:\\.|[^`\\])*`|\S/g;

// Shape n-grams (identifiers -> I, literals -> L) + the identifier set.
export function features(text) {
  const shape = [];
  const idents = new Set();
  for (const [t] of text.matchAll(TOKEN)) {
    if (/^[A-Za-z_$]/.test(t)) {
      if (KEYWORDS.has(t)) shape.push(t);
      else {
        shape.push("I");
        idents.add(t);
      }
    } else shape.push(/^[\d"'`]/.test(t) ? "L" : t);
  }
  const grams = new Set();
  for (let i = 0; i + GRAM <= shape.length; i++) grams.add(shape.slice(i, i + GRAM).join(" "));
  return { grams, idents };
}

const jaccard = (a, b) => {
  let n = 0;
  for (const x of a) if (b.has(x)) n++;
  return n / (a.size + b.size - n || 1);
};
const overlaps = (a, b) => a.file === b.file && a.start <= b.end && b.start <= a.end;

// pool -> (target -> up to NEIGHBOURS same-kind pool units by 0.5*shape +
// 0.5*identifier Jaccard, skipping anything overlapping the target or an
// earlier pick). Memoised per target.
export function makeNearest(pool) {
  const feat = new Map();
  const f = (u) => feat.get(u) ?? feat.set(u, features(u.text)).get(u);
  const index = new Map();
  pool.forEach((u, i) => {
    for (const g of f(u).grams) {
      if (!index.has(g)) index.set(g, []);
      index.get(g).push(i);
    }
  });
  const memo = new Map();
  return (t) => {
    const k = `${t.file}:${t.start}-${t.end}`;
    if (memo.has(k)) return memo.get(k);
    const tf = f(t);
    const shared = new Map();
    for (const g of tf.grams) {
      const l = index.get(g);
      if (l && l.length <= STOP_GRAM) for (const i of l) shared.set(i, (shared.get(i) ?? 0) + 1);
    }
    const scored = [];
    for (const [i, s] of shared) {
      const u = pool[i];
      if (overlaps(u, t) || (t.kind !== "top" && u.kind !== t.kind)) continue;
      const uf = f(u);
      const sim = 0.5 * (s / (tf.grams.size + uf.grams.size - s)) + 0.5 * jaccard(tf.idents, uf.idents);
      if (sim >= MIN_SIM) scored.push({ unit: u, sim });
    }
    const picks = [];
    for (const c of scored.sort((a, b) => b.sim - a.sim)) {
      if (picks.length >= NEIGHBOURS) break;
      if (!picks.some((p) => overlaps(p.unit, c.unit))) picks.push(c);
    }
    memo.set(k, picks);
    return picks;
  };
}

// Lines worth keeping when a long unit is clipped: where control leaves with
// an error/status/value -- the evidence most bug probes need.
const EXIT_LINE = /\breturn\b|\bErr\(|\?;|\bbail!|\banyhow!|StatusCode|\bstatus\b|\bthrow\b|\breject\(|\bpanic!|\bunreachable!/;

// Unit text with '+' on changed lines (all lines when unchanged: reviewed
// whole). Longer than `max` lines: keep the changed region +-20 lines, plus
// every exit line +-1 anywhere in the unit, with `…` for the gaps.
export function render(u, max = MAX_UNIT_LINES) {
  const lines = u.text.split("\n");
  const ch = u.changed?.size ? [...u.changed] : null;
  const mark = (i) => (!ch || u.changed.has(u.start + i) ? "+ " : "  ") + lines[i];
  if (lines.length <= max) return lines.map((_, i) => mark(i)).join("\n");
  const keep = new Set();
  const add = (a, b) => {
    for (let i = Math.max(0, a); i <= Math.min(lines.length - 1, b); i++) keep.add(i);
  };
  add(0, 0);
  add(lines.length - 1, lines.length - 1);
  if (ch) add(Math.min(...ch) - u.start - 20, Math.max(...ch) - u.start + 20);
  else add(0, Math.floor(max / 2));
  lines.forEach((t, i) => {
    if (EXIT_LINE.test(t)) add(i - 1, i + 1);
  });
  const out = [];
  let prev = -1;
  for (const i of [...keep].sort((a, b) => a - b)) {
    if (i > prev + 1) out.push(`  … (${i - prev - 1} lines)`);
    out.push(mark(i));
    prev = i;
  }
  return out.join("\n");
}

// The changed lines only (the whole unit when unchanged) -- what gates test.
export const changedText = (u) =>
  u.changed?.size ? u.text.split("\n").filter((_, i) => u.changed.has(u.start + i)).join("\n") : u.text;

const span = (u) => `${u.file}:${u.start}-${u.end}`;
const label = (u) => `${span(u)} ${u.name}`;
const hash = (x) => createHash("sha1").update(typeof x === "string" ? x : JSON.stringify(x)).digest("hex");

// Run fn over items with at most n in flight; results keep input order.
async function pool(items, n, fn) {
  const out = new Array(items.length);
  let next = 0;
  const worker = async () => {
    while (next < items.length) {
      const i = next++;
      out[i] = await fn(items[i], i);
    }
  };
  await Promise.all(Array.from({ length: Math.min(n, items.length) }, worker));
  return out;
}

function semaphore(n) {
  let active = 0;
  const queue = [];
  const release = () => {
    active--;
    queue.shift()?.();
  };
  return async (fn) => {
    if (active >= n) await new Promise((r) => queue.push(r));
    active++;
    try {
      return await fn();
    } finally {
      release();
    }
  };
}

// ---- probes -----------------------------------------------------------------

// A probe file is an ES module (node: builtins only; it is imported from a
// content-addressed copy, so relative imports don't resolve):
//   export const meta = { description, langs?, kinds?, gate?, routable? }
//   export default async function (unit, r) { return { p, label, note? } | null }
// Loaded by content hash: an edited probe takes effect on the next call.
const modules = new Map();
export async function loadProbe(name, src, source, file) {
  const h = hash(src).slice(0, 16);
  if (!modules.has(h)) {
    const dir = path.join(tmpdir(), "jev-probes-mod");
    const f = path.join(dir, `${name}-${h}.mjs`);
    modules.set(
      h,
      mkdir(dir, { recursive: true })
        .then(() => writeFile(f, src))
        .then(() => import(pathToFileURL(f).href))
    );
  }
  let mod;
  try {
    mod = await modules.get(h);
  } catch (e) {
    modules.delete(h);
    throw e;
  }
  if (typeof mod.meta?.description !== "string") throw new Error("must `export const meta = { description: ... }`");
  const q = mod.meta.question;
  if (q !== undefined && typeof q !== "function" && (typeof q?.ask !== "string" || typeof q?.options !== "object"))
    throw new Error("meta.question must be { ask: string, options: {label: description} } or (unit, r) => that");
  if (typeof mod.default !== "function" && q === undefined)
    throw new Error("needs `meta.question` (declarative) or `export default async function (unit, r)` (code)");
  return { name, source, file, meta: mod.meta, fn: typeof mod.default === "function" ? mod.default : null };
}

// A declarative probe's question for a unit, as a Jev choice.
const declQuestion = (p, u, r) => {
  const q = typeof p.meta.question === "function" ? p.meta.question(u, r) : p.meta.question;
  return choice(`${q.ask}\n${SCOPE}`, q.options);
};

// Run any probe on a unit: declarative -> one cached choice; code -> its function.
async function evalProbe(p, u, r) {
  if (p.fn) return p.fn(u, r);
  const q = declQuestion(p, u, r);
  return toFinding(readAnswer((await r.ask({ q })).q, q.criteria));
}

// [[dir, source], ...] -> Map(name -> probe); later dirs override earlier ones.
// A probe that fails to load is kept with `error` so it shows up in listings.
export async function loadProbes(dirs) {
  const out = new Map();
  for (const [dir, source] of dirs) {
    let files;
    try {
      files = (await readdir(dir)).filter((f) => f.endsWith(".mjs")).sort();
    } catch {
      continue;
    }
    for (const f of files) {
      const name = f.slice(0, -4);
      const file = path.join(dir, f);
      try {
        out.set(name, await loadProbe(name, await readFile(file, "utf8"), source, file));
      } catch (e) {
        out.set(name, { name, source, file, meta: {}, error: e.message });
      }
    }
  }
  return out;
}

// The tag whitelist: a probe only ever sees units of its langs/kinds.
export const applies = (p, u) => !p.error && (!p.meta.langs || p.meta.langs.includes(u.lang)) && (!p.meta.kinds || p.meta.kinds.includes(u.kind));

// gate: RegExp, { rust: RegExp, typescript: RegExp }, or (unit, r) => bool.
// Regexes test the changed lines, or the whole unit with meta.gateOn:
// "unit" (for bugs where the change is small but the evidence isn't: a new
// `continue` in front of an unchanged status mapping). No gate: passes.
async function gatePasses(p, u, r) {
  const g = p.meta.gate;
  if (!g) return true;
  if (typeof g === "function") return Boolean(await g(u, r));
  const re = g instanceof RegExp ? g : g[u.lang];
  return re ? re.test(p.meta.gateOn === "unit" ? u.text : changedText(u)) : false;
}

// Base Jev state for a unit: the unit plus its nearest same-kind neighbours.
function unitState(rv, u) {
  return {
    lang: LANG_NAMES[u.lang],
    kind: u.kind,
    unit_path: span(u),
    unit: render(u, rv.maxLines),
    neighbours: rv.nearest(u).map((n) => ({
      path: span(n.unit),
      similarity: Number(n.sim.toFixed(2)),
      code: n.unit.text.split("\n").slice(0, NEIGHBOUR_LINES).join("\n"),
    })),
  };
}

// Cached, budgeted, de-duplicated Jev request. questions: { id: question }.
class BudgetError extends Error {
  constructor() {
    super("Jev budget exhausted");
  }
}
const isBudget = (e) => e instanceof BudgetError || e?.message === "Jev budget exhausted";
async function askCached(rv, state, questions) {
  const ids = Object.keys(questions);
  const keys = ids.map((k) => hash([state, questions[k]]));
  const missing = ids.map((k, i) => [k, keys[i]]).filter(([, key]) => !rv.cache.has(key) && !rv.inflight.has(key));
  if (missing.length) {
    if (rv.budget.left <= 0) throw new BudgetError();
    rv.budget.left--;
    rv.budget.used++;
    rv.budget.questions += missing.length;
    const req = Object.fromEntries(missing.map(([k], j) => [`q${j}`, questions[k]]));
    const p = rv.limit(() => rv.ask(state, req, rv.signal)).then((res) => {
      missing.forEach(([, key], j) => {
        if (res.answers?.[`q${j}`]) rv.cache.set(key, res.answers[`q${j}`]);
      });
    });
    for (const [, key] of missing) rv.inflight.set(key, p);
    p.catch(() => {}).finally(() => {
      for (const [, key] of missing) rv.inflight.delete(key);
    });
  }
  await Promise.all(keys.map((k) => rv.inflight.get(k)).filter(Boolean));
  return Object.fromEntries(
    ids.map((k, i) => {
      if (!rv.cache.has(keys[i])) throw new Error("no answer from Jev");
      return [k, rv.cache.get(keys[i])];
    })
  );
}

// The `r` a probe gets. Everything Jev-facing is cached and budgeted.
function runtime(rv, unit, depth, stack) {
  const r = {
    unit,
    depth,
    args: rv.args,
    repo: rv.root,
    dir: rv.dir,
    units: rv.all,
    lang: unit.lang,
    langName: LANG_NAMES[unit.lang],
    budget: rv.budget,
    render: (u = unit) => render(u, rv.maxLines),
    label: (u = unit) => label(u),
    changedText: (u = unit) => changedText(u),
    nearest: (u = unit) => rv.nearest(u),
    state: (extra = {}, u = unit) => ({ ...unitState(rv, u), ...extra }),
    ask: (questions, state = r.state()) => askCached(rv, state, questions),
    noul: async (question, state) => {
      const a = (await r.ask({ q: { type: "noul", instructions: `${question}\n${SCOPE}` } }, state)).q;
      if (!Number.isFinite(a?.noul)) throw new Error("malformed Jev noul answer");
      return a.noul;
    },
    choose: async (question, options, state) => {
      const q = choice(`${question}\n${SCOPE}`, options);
      return readAnswer((await r.ask({ q }, state)).q, q.criteria);
    },
    score: async (question, levels, state) =>
      (await r.ask({ q: { type: "score", instructions: `${question}\n${SCOPE}`, criteria: levels } }, state)).q,
    finding: toFinding,
    run: (cmd, argv = [], { timeout = 30_000, cwd = rv.dir } = {}) => run(TOOLS[cmd] ?? cmd, argv, cwd, rv.signal, timeout),
    read: (file) => readFile(path.join(rv.dir, file), "utf8"),
    probe: async (name, u = unit) => {
      const p = rv.probes.get(name);
      if (!p) throw new Error(`unknown probe ${name}`);
      if (depth + 1 > MAX_DEPTH || stack.includes(name)) {
        rv.stats.depthHits++;
        return null;
      }
      if (!applies(p, u)) return null;
      const out = normFinding(await evalProbe(p, u, runtime(rv, u, depth + 1, [...stack, name])));
      return out.ok ? null : out;
    },
  };
  return r;
}

async function invoke(rv, p, u) {
  rv.stats.run++;
  let timer;
  try {
    const out = await Promise.race([
      evalProbe(p, u, runtime(rv, u, 0, [p.name])),
      new Promise((_, rej) => (timer = setTimeout(() => rej(new Error(`timed out after ${PROBE_TIMEOUT / 1000}s`)), PROBE_TIMEOUT))),
    ]);
    return normFinding(out);
  } catch (e) {
    return isBudget(e) ? { skipped: true } : { error: e.message };
  } finally {
    clearTimeout(timer);
  }
}

const routeQuestion = (p) => ({
  type: "noul",
  instructions:
    `Could the changed lines plausibly have this problem: ${p.meta.description}? ` +
    "Answer yes only if the changed code contains logic where it could actually occur; this only decides whether to run a closer check.\n" +
    SCOPE,
});

// One unit: whitelist -> gates -> ONE Jev request holding every applicable
// declarative probe's question, the routing question of every applicable
// code probe, and the agent's questions -> then the routed/forced/"always"
// code probes run. Declarative probes are never routed: their question IS
// the check, so routing would ask it twice and add a threshold to jitter on.
async function reviewUnit(rv, u) {
  const r0 = runtime(rv, u, 0, []);
  const results = {};
  const forced = [];
  // Forced probes skip routing, not their gate: the gate says when the probe
  // makes sense at all (forcing reentrant-caller onto side-effect-free fns
  // walked their callers and lit them up). jev_probe dry runs set ungated --
  // pointing a probe at a unit to test it should run it.
  for (const n of rv.forced) {
    const p = rv.probes.get(n);
    if (!p) results[n] = { error: "unknown probe" };
    else if (p.error) results[n] = { error: `failed to load: ${p.error}` };
    else if (!applies(p, u)) continue;
    else if (rv.args.ungated) forced.push(p);
    else {
      try {
        if (await gatePasses(p, u, r0)) forced.push(p);
        else rv.stats.gatedOut++;
      } catch (e) {
        results[p.name] = { error: `gate: ${e.message}` };
      }
    }
  }
  const candidates = [];
  if (rv.route) {
    for (const p of rv.probes.values()) {
      if (p.meta.routable === false || rv.forced.includes(p.name) || !applies(p, u)) continue;
      try {
        if (await gatePasses(p, u, r0)) candidates.push(p);
      } catch (e) {
        results[p.name] = { error: `gate: ${e.message}` };
      }
    }
  }
  const direct = [...forced, ...candidates].filter((p) => !p.fn);
  const toRoute = candidates.filter((p) => p.fn && p.meta.routable !== "always");
  const qs = {};
  for (const p of direct) {
    try {
      qs[`probe:${p.name}`] = declQuestion(p, u, r0);
    } catch (e) {
      results[p.name] = { error: `question: ${e.message}` };
    }
  }
  for (const p of toRoute) qs[`route:${p.name}`] = routeQuestion(p);
  for (const [k, q] of Object.entries(rv.args.questions ?? {})) {
    qs[`ask:${k}`] = choice(`${q.ask}\n${SCOPE}`, q.options ?? { violated: "yes, the changed code has this problem", ok: "no, it does not", na: "the question does not apply to this code" });
  }
  let answers = {};
  if (Object.keys(qs).length) {
    try {
      answers = await askCached(rv, unitState(rv, u), qs);
    } catch (e) {
      if (isBudget(e)) return { skipped: true };
      results.jev = { error: e.message };
    }
  }
  const read = (key, name) => {
    const a = answers[key];
    if (!a) return;
    try {
      results[name] = toFinding(readAnswer(a, qs[key].criteria)) ?? { ok: true };
    } catch (e) {
      results[name] = { error: e.message };
    }
  };
  for (const p of direct) if (qs[`probe:${p.name}`]) read(`probe:${p.name}`, p.name);
  rv.stats.direct += direct.length;
  const routed = toRoute.filter((p) => (answers[`route:${p.name}`]?.noul ?? 0) >= ROUTE_MIN);
  rv.stats.candidates += toRoute.length;
  rv.stats.routed += routed.length;
  for (const k of Object.keys(rv.args.questions ?? {})) read(`ask:${k}`, k);
  const run = [...forced.filter((p) => p.fn), ...candidates.filter((p) => p.fn && p.meta.routable === "always"), ...routed];
  const outs = await Promise.all(run.map((p) => invoke(rv, p, u)));
  run.forEach((p, i) => {
    if (!outs[i].skipped) results[p.name] = outs[i];
  });
  return results;
}

export function formatLine(r) {
  if (r.results.skipped) return `${label(r.unit)}\t-\tskipped (budget)`;
  const parts = [];
  const ok = [];
  for (const [k, x] of Object.entries(r.results)) {
    if (x.error) parts.push(`${k}: error ${x.error}`);
    else if (x.abstain) parts.push(`${k}: ${IE}`);
    else if (x.ok || x.p < 0.1) ok.push(k);
    else parts.push(`${k}: ${x.label} ${x.p.toFixed(2)}${x.note ? ` ${x.note}` : ""}`);
  }
  if (ok.length) parts.push(`ok: ${ok.join(", ")}`);
  return `${label(r.unit)}\t${r.score == null ? "-" : r.score.toFixed(2)}\t${parts.join(" · ") || "no probes applied"}`;
}

const scoreOf = (results, rankBy) => {
  if (results.skipped) return null;
  const xs = rankBy ? [results[rankBy]] : Object.values(results);
  const ps = xs.filter((x) => x && !x.error && !x.abstain).map((x) => (x.ok ? 0 : x.p));
  return ps.length ? Math.max(...ps) : null;
};

// Everything after `git diff`. `dir` is the tree the diff's new side lives
// in; `ask(state, questions, signal)` is the Jev call (injected so tests run
// offline); `cache` persists across calls; `probeDirs` lists probe libraries
// (later overrides earlier); `extraProbes` adds loaded probes (jev_probe's
// unsaved scripts).
export async function runReview(args, { dir, root, diff, ask, cache, signal, probeDirs, extraProbes = [], note }) {
  const changed = changedLines(diff);
  const skippedFiles = unreviewedFiles(diff);
  const notReviewed = skippedFiles.length ? `not reviewed: ${skippedFiles.slice(0, 20).join(" · ")}${skippedFiles.length > 20 ? ` · +${skippedFiles.length - 20} more` : ""}` : "";
  if (!changed.size && !args.units?.length)
    return notReviewed ? `No added Rust/TypeScript lines; ${notReviewed}` : "No changes in that diff.";

  const probes = await loadProbes(probeDirs ?? [[SHIPPED_PROBES, "shipped"], [USER_PROBES, "user"]]);
  for (const p of extraProbes) probes.set(p.name, p);

  let all = await scanUnits(dir, signal);
  const fileLines = new Map();
  for (const f of changed.keys()) fileLines.set(f, (await readFile(path.join(dir, f), "utf8")).split("\n"));
  all = all.map((u) => (fileLines.has(u.file) ? withAttrs(u, fileLines.get(u.file)) : u));
  const cu = changedUnits(all, changed, fileLines);
  const { units: selected, unmatched } = selectUnits(all, cu, args.units, !args.tests);
  const testsSkipped = args.units?.length ? 0 : cu.filter((u) => u.test).length * !args.tests;
  const targets = selected.slice(0, MAX_UNITS);

  const candidates = all.filter((u) => u.end - u.start + 1 >= 3 && u.end - u.start < MAX_UNIT_LINES && !TEST_PATH.test(u.file));
  const rv = {
    args,
    root,
    dir,
    all,
    signal,
    ask,
    cache,
    probes,
    maxLines: args.max_lines ?? MAX_UNIT_LINES,
    inflight: new Map(),
    limit: semaphore(CONCURRENCY),
    nearest: makeNearest(candidates.slice(0, MAX_POOL)),
    budget: { left: args.budget ?? MAX_CALLS, used: 0, questions: 0 },
    route: args.route ?? !(args.questions || args.probes),
    forced: [...new Set([...(args.probes ?? []), ...(args.criteria ? ["rules"] : [])])],
    stats: { run: 0, routed: 0, candidates: 0, direct: 0, depthHits: 0, gatedOut: 0 },
  };

  const reviewed = await pool(targets, CONCURRENCY, async (u) => {
    const results = await reviewUnit(rv, u);
    return { unit: u, results, score: scoreOf(results, args.rank_by) };
  });
  reviewed.sort((a, b) => (b.score ?? -1) - (a.score ?? -1) || Boolean(a.results.skipped) - Boolean(b.results.skipped));

  const broken = [...probes.values()].filter((p) => p.error).map((p) => p.name);
  const budgetSkipped = reviewed.filter((r) => r.results.skipped).length;
  const bare = reviewed.filter((r) => !r.results.skipped && !Object.keys(r.results).length).length;
  const s = rv.stats;
  const head =
    `repo: ${root}` +
    (note ? ` · ${note}` : "") +
    ` · ${targets.length} unit(s)` +
    (testsSkipped ? `, ${testsSkipped} test unit(s) skipped` : "") +
    (bare ? `, ${bare} with no probes applied` : "") +
    ` · ${rv.budget.used} Jev request(s) / ${rv.budget.questions} question(s), budget left ${rv.budget.left}` +
    (budgetSkipped ? ` · ${budgetSkipped} unit(s) skipped: budget exhausted` : "") +
    ` · probes: ${s.direct} asked directly, ${s.run} code run(s)` +
    (s.candidates ? `, routed ${s.routed}/${s.candidates}` : "") +
    (s.gatedOut ? ` · ${s.gatedOut} forced probe×unit gated out` : "") +
    (s.depthHits ? ` · ${s.depthHits} r.probe call(s) cut at depth ${MAX_DEPTH}/cycle` : "") +
    (selected.length > targets.length ? ` · capped, ${selected.length - targets.length} unit(s) skipped` : "") +
    (candidates.length > MAX_POOL ? ` · neighbour search limited to ${MAX_POOL} units` : "") +
    (unmatched.length ? ` · unmatched units: ${unmatched.join(", ")}` : "") +
    (broken.length ? ` · probes failing to load: ${broken.join(", ")} (jev_probe list)` : "") +
    (notReviewed ? ` · ${notReviewed}` : "");
  return [head, ...reviewed.slice(0, args.top ?? 20).map(formatLine)].join("\n");
}

// ---- git --------------------------------------------------------------------

// `target` (a repo, a dir inside one, or a file; relative to `directory`,
// `~` expanded) picks BOTH the repo and the pathspec: git runs from the
// target's directory, so a session dir that holds several repos (or is
// itself an empty outer repo) still reaches the right one. Throws with the
// directory in the message. Returns { root, diff, note }.
//
// A plain `from` that is not an ancestor of the new side (`to`, else HEAD) --
// e.g. `main` after main moved on -- would pull main's own new commits into
// the review as if they were removed/added here. Diff from the merge-base
// instead and say so in `note`. `a...b` / `a..b` ranges pass through as-is.
export async function gitDiff(directory, { from, to, target }, signal) {
  const t = (target ?? ".").replace(/^~(?=\/|$)/, homedir());
  const abs = path.resolve(directory, t);
  let st;
  try {
    st = await stat(abs);
  } catch {
    throw new Error(`no such path: ${abs}`);
  }
  const cwd = st.isDirectory() ? abs : path.dirname(abs);
  const spec = st.isDirectory() ? "." : path.basename(abs);
  try {
    const root = (await git(cwd, ["rev-parse", "--show-toplevel"], signal)).trim();
    let base = from;
    let note;
    if (!from.includes("..")) {
      const tip = to ?? "HEAD";
      const isAncestor = await git(cwd, ["merge-base", "--is-ancestor", from, tip], signal).then(
        () => true,
        () => false
      );
      if (!isAncestor) {
        const mb = await git(cwd, ["merge-base", from, tip], signal).then((s) => s.trim(), () => "");
        if (mb) {
          base = mb;
          note = `from ${from} → merge-base ${mb.slice(0, 10)} (${from} is not an ancestor of ${tip})`;
        }
      }
    }
    const argv = ["diff", "--no-color", "--no-ext-diff", "--no-relative", "-U3", base];
    if (to) argv.push(to);
    argv.push("--", spec);
    return { root, diff: await git(cwd, argv, signal), note };
  } catch (e) {
    throw new Error(`git failed in ${cwd}: ${e.message}`);
  }
}

// The tree at `ref`, extracted once per tree sha (git archive), so units and
// line numbers match a `to` that isn't the working tree.
const trees = new Map();
export async function treeAt(root, ref, signal) {
  const sha = (await git(root, ["rev-parse", "--verify", `${ref}^{tree}`], signal)).trim();
  if (!trees.has(sha)) {
    const dir = await mkdtemp(path.join(tmpdir(), "jev-review-"));
    await git(root, ["archive", "--format=tar", "-o", path.join(dir, ".tree.tar"), sha], signal);
    await run("tar", ["-xf", ".tree.tar"], dir, signal);
    trees.set(sha, dir);
  }
  return trees.get(sha);
}

// ---- probe library (jev_probe) ----------------------------------------------

async function saveProbe(dir, name, script, message) {
  await mkdir(dir, { recursive: true });
  try {
    await stat(path.join(dir, ".git"));
  } catch {
    await git(dir, ["init", "-q"]);
  }
  await writeFile(path.join(dir, `${name}.mjs`), script);
  try {
    await git(dir, ["add", "--", `${name}.mjs`]);
    await git(dir, ["commit", "-q", "-m", message || `probe ${name}`]);
  } catch {
    // nothing to commit -- fine; the repo is a safety net, not a gate
  }
}

export async function listProbes(dirs, filter) {
  const probes = await loadProbes(dirs);
  const needle = typeof filter === "string" && filter !== "true" ? filter.toLowerCase() : null;
  const lines = [];
  for (const p of probes.values()) {
    const m = p.meta;
    const mode = m.routable === false ? "forced only" : !p.fn ? "direct" : m.routable === "always" ? "always" : "routed";
    const row =
      `${p.name}\t${p.source}\t${m.langs?.join(",") ?? "all langs"}${m.kinds ? ` [${m.kinds.join(",")}]` : ""}` +
      `\t${mode}${m.gate ? `, gated${m.gateOn === "unit" ? " on unit" : ""}` : ""}` +
      `\t${p.error ? `LOAD ERROR: ${p.error}` : m.description}`;
    if (!needle || row.toLowerCase().includes(needle)) lines.push(row);
  }
  return lines.join("\n") || "No probes.";
}

// ---- Jev --------------------------------------------------------------------

let cachedKey = null;
async function apiKey() {
  cachedKey ||= process.env.TYPESAFE_API_KEY?.trim() || (await readFile("/run/secrets/jev/api-key", "utf8")).trim();
  return cachedKey;
}

async function jevAsk(state, questions, signal) {
  const body = JSON.stringify({ model: "jev-latest", state, questions });
  for (let attempt = 0; ; attempt++) {
    const res = await fetch(ENDPOINT, {
      method: "POST",
      headers: { Authorization: `Bearer ${await apiKey()}`, "Content-Type": "application/json" },
      body,
      signal: AbortSignal.any([signal, AbortSignal.timeout(30_000)].filter(Boolean)),
    });
    if ([429, 503, 529].includes(res.status) && attempt < 2) {
      await new Promise((r) => setTimeout(r, 500 * 2 ** attempt));
      continue;
    }
    if (!res.ok) throw new Error(`Jev HTTP ${res.status}: ${(await res.text()).slice(0, 200)}`);
    return res.json();
  }
}

// ---- tools ------------------------------------------------------------------

const REVIEW_DESCRIPTION = `Inspect changed Rust/TypeScript code with Jev, a fast decision model that answers typed questions. You steer: what to ask, where, and which probes run. ~1s per pass.

- Units: each changed function/impl/struct/class/const (tree-sitter; Rust units include their #[...] attributes), with '+' on changed lines and its 2 most similar existing units of the same kind as context. A small changed impl/class (header changed, <= ${FOLD_LINES} lines) is one unit; otherwise its changed children are the units (mods always split). Units over \`max_lines\` keep the changed region plus every return/error/status line. Test code (#[test], #[cfg(test)] mods, tests/, *.test.ts, *.spec.ts) is skipped unless \`tests: true\` or picked explicitly. Deleted/renamed/removals-only/non-code files are listed in the header as "not reviewed".
- Probes: a library of small checks (list with jev_probe). Default pass, per unit: every probe whose langs/kinds fit and whose deterministic gate passes runs. Question-only probes are asked directly in ONE request per unit together with your \`questions\`; code probes are routed (Jev says whether they're plausible) or always run. \`probes: [names]\` runs exactly those instead.
- Your own \`questions\` (a choice per unit; default options violated/ok/na) go in the same request. Giving \`questions\` or \`probes\` turns routing off unless \`route: true\`. Spell out close alternatives as separate options (e.g. silent / logged / propagated) instead of yes/no -- in practice the most reliable signal you get.
- Iterate: start broad with the defaults plus 5-10 suspicions specific to this change as \`questions\`, then narrow with \`units\`. Every answer is cached, so repeats only pay for new questions. A check you will want again belongs in a probe (jev_probe).
- Output: \`repo:\` header, then \`path:start-end name<TAB>p<TAB>findings\`, worst first; p is the max over findings (\`rank_by\` picks one probe/question). p is a ranking signal, not calibrated; scores move ~±0.05 between identical runs. \`insufficient_evidence\` is an abstention, never a pass.
- \`path\` picks the repo (git runs from there; relative or ~). Refs resolve in THAT repo. Without \`to\`, compares \`from\` against the working tree. A \`from\` that isn't an ancestor (e.g. main after it moved on) is replaced by the merge-base; the header says so.`;

const PROBE_DESCRIPTION = `Manage the probe library jev_review uses. A probe checks ONE kind of problem on ONE code unit. Two shapes:

Question-only (preferred): asked directly, bundled into the unit's single Jev request.
\`\`\`js
export const meta = {
  description: "…",            // what it finds
  langs: ["rust"],              // whitelist; omit = all ("rust", "typescript")
  kinds: ["fn", "impl"],        // whitelist; fn impl type mod (rust), fn class type const (ts), top
  gate: /\\.unwrap\\(/,           // deterministic pre-filter: RegExp, {rust, typescript}, or (unit, r) => bool
  gateOn: "changed",            // regex tests the changed lines (default) or "unit" (whole unit: a small change can expose unchanged code)
  question: {                   // or (unit, r) => {ask, options}
    ask: "Question about the changed lines?",
    options: { bad: "…", fine: "…", na: "does not apply" },  // distinct alternatives beat yes/no
  },
};
\`\`\`
Code (when it needs evidence beyond the unit: callers via r.run("rg"), other units, files, other probes):
\`\`\`js
export const meta = { description, langs, kinds, gate, gateOn,
  routable: true };             // true = Jev decides from the unit (routing); "always" = run when the gate passes (use it when the evidence isn't in the unit); false = only when named in probes
export default async function (unit, r) {
  const a = await r.choose("Question?", { bad: "…", fine: "…", na: "does not apply" });
  return r.finding(a);          // or { p, label, note } or null (nothing found)
}
\`\`\`
\`unit\`: {file, lang, kind, start, end, name, text, changed: Set<line>|null, test}. \`r\`: noul(q, state?) -> 0..1 · choose(q, options, state?) -> {choice, p, labels, abstain, probabilities} · score(q, levels, state?) · ask({id: question}, state?) raw · state(extra?, unit?) (default: unit + neighbours) · finding(chooseResult) · nearest(unit?) -> [{unit, sim}] · units (all) · render(unit?) · changedText(unit?) · label(unit?) · run(cmd, args, {timeout}) -> stdout, any binary, cwd = repo tree · read(path) · probe(name, unit?) -> finding|null (recursion, depth <= ${MAX_DEPTH}, whitelists apply) · args (jev_review args) · budget. All Jev calls are cached and count against one per-review budget. Options named none/ok/na/no/safe/consistent/… or prefixed \`ok_\` (e.g. ok_invariant) don't count as findings; \`minor_\` options (e.g. minor_vague) count at half weight. node: builtins only, no relative imports.

Shapes: \`list\` (true or a filter) · \`name\` + \`script\` saves to ~/scratch/jev-probes/<name>.mjs (git-committed; overrides a shipped probe of that name), then dry-runs it if \`units\` is given · \`script\` alone dry-runs unsaved (needs \`units\`) · \`name\` alone dry-runs a saved probe on \`units\`. Dry runs take the same \`path\`/\`from\`/\`to\` as jev_review (default from=HEAD).`;

async function server() {
  const require = createRequire((process.env.HOME || "/root") + "/.config/opencode/package.json");
  const { z } = require("zod");
  const cache = new Map(); // ponytail: unbounded, per opencode process; an LRU if long sessions bloat it
  const dirs = [[SHIPPED_PROBES, "shipped"], [USER_PROBES, "user"]];
  const rules = z.record(z.string(), z.string());
  const where = {
    from: z.string().describe("Base ref, e.g. HEAD, main, a merge-base sha"),
    to: z.string().optional().describe("Target ref. Omit to diff against the working tree."),
    path: z
      .string()
      .optional()
      .describe("Repo to review, or a dir/file inside one; relative to the session directory, ~ ok. Picks the repo and limits the diff to it."),
    units: z
      .array(z.string())
      .optional()
      .describe("Only these units: `file:line` (any unit, changed or not; pasted output labels work) or a path prefix (changed units under it). Paths relative to the repo root."),
  };

  async function review(args, ctx, extraProbes) {
    const { root, diff, note } = await gitDiff(ctx.directory, { from: args.from, to: args.to, target: args.path }, ctx.abort);
    const dir = args.to ? await treeAt(root, args.to, ctx.abort) : root;
    return runReview(args, { dir, root, diff, ask: jevAsk, cache, signal: ctx.abort, probeDirs: dirs, extraProbes, note });
  }

  return {
    tool: {
      jev_review: {
        description: REVIEW_DESCRIPTION,
        args: {
          ...where,
          probes: z.array(z.string()).optional().describe("Run exactly these probes (by name) on every unit whose langs/kinds fit and whose gate passes; turns routing off unless route: true."),
          route: z.boolean().optional().describe("Let Jev route each unit to library probes. Default: on unless questions/probes are given."),
          questions: z
            .record(
              z.string(),
              z.object({
                ask: z.string().describe("The question, about the changed lines"),
                options: rules.optional().describe("{label: description}. Name the no-problem options none/ok/na. Default: violated/ok/na."),
              })
            )
            .optional()
            .describe("Your own questions for this pass, keyed by name."),
          criteria: z
            .object({ rust: rules.optional(), typescript: rules.optional(), all: rules.optional() })
            .optional()
            .describe("Named style rules {rule-name: description} per language (or `all`); runs the `rules` probe with them."),
          tests: z.boolean().optional().describe("Include test code (default: skipped)."),
          rank_by: z.string().optional().describe("Rank by this one probe/question instead of the max over all."),
          budget: z.number().int().positive().optional().describe(`Max Jev requests for this call (default ${MAX_CALLS}); one request carries all of a unit's questions.`),
          max_lines: z
            .number()
            .int()
            .positive()
            .optional()
            .describe(`Units longer than this are shown as the changed region +-20 lines plus every return/error/status line (default ${MAX_UNIT_LINES}).`),
          top: z.number().int().positive().optional().describe("How many units to list (default 20)"),
        },
        async execute(args, ctx) {
          try {
            return { title: `${args.from}${args.to ? `..${args.to}` : ""}`, output: await review(args, ctx) };
          } catch (e) {
            return e.message;
          }
        },
      },
      jev_probe: {
        description: PROBE_DESCRIPTION,
        args: {
          list: z.union([z.boolean(), z.string()]).optional().describe("List probes (true) or filter by substring."),
          name: z.string().optional().describe("Probe name ([a-z0-9-]). With script: save. Alone: dry-run the saved probe."),
          script: z.string().optional().describe("Probe module source."),
          message: z.string().optional().describe("Git commit message for a save."),
          ...where,
          from: where.from.optional(),
        },
        async execute(args, ctx) {
          try {
            if (args.list && args.list !== "false") return await listProbes(dirs, args.list);
            if (args.name && !/^[a-z0-9][a-z0-9-]*$/.test(args.name)) return "Error: name must match [a-z0-9][a-z0-9-]*";
            let extra = [];
            let saved = "";
            if (args.script) {
              const probe = await loadProbe(args.name ?? "inline", args.script, args.name ? "user" : "inline");
              if (args.name) {
                await saveProbe(USER_PROBES, args.name, args.script, args.message);
                saved = `Saved ${args.name} to ${path.join(USER_PROBES, args.name + ".mjs")}.`;
              } else extra = [probe];
            } else if (!args.name) return "Error: give list, name, or script.";
            if (!args.units?.length) return saved || "Error: dry runs need `units`.";
            const out = await review(
              { from: args.from ?? "HEAD", to: args.to, path: args.path, units: args.units, probes: [args.name ?? "inline"], route: false, tests: true, ungated: true },
              ctx,
              extra
            );
            return [saved, out].filter(Boolean).join("\n");
          } catch (e) {
            return `Error: ${e.message}`;
          }
        },
      },
    },
  };
}

// V1 shape: the named exports above are not plugins (see pkgs/axiom-ledger).
export default { id: "jev-review", server };

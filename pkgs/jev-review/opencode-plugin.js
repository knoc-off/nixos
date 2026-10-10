// OpenCode plugin: jev_run / jev_review / jev_probe -- a language- and
// task-agnostic inspection engine the calling agent steers.
//
// Jev (TypeSafe's System One model) never writes text; it answers typed
// questions (choice / noul / score) fast and cheap. The calling LLM plans.
// Three kinds of small JS modules (shipped next to this file, user ones in
// ~/scratch/jev-probes, overriding by name) plug into one engine:
//
//   harness  WHAT to look at and how to frame it: produces units (any text
//            spans: diff hunks, functions, comments, files) + a scope sentence.
//            Shipped: `review` (changed code in a git diff). jev_review = jev_run
//            with harness "review".
//   lang     HOW to split a language into units: ast-grep kinds, trivial/test
//            patterns, optional attach/isTest hooks. Files with no lang still
//            work: their changed lines become `top` units.
//   probe    ONE check on ONE unit: a question, or code using r.run/r.probe.
//
//   harness.units()                          -> units (+ all units, for neighbours)
//   per unit: probe whitelist (langs/kinds) -> gates (deterministic)
//             -> ONE Jev request: direct probe questions + routing questions + agent questions
//             -> run the routed code probes (recursion via r.probe, depth <= 3, shared budget)
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
// probes/, harnesses/, langs/ live here (the source dir, or $out/lib/jev-review).
const SHARE = "@shareDir@".startsWith("@") ? fileURLToPath(new URL(".", import.meta.url)) : "@shareDir@";
const RG = "@rg@".startsWith("@") ? "rg" : "@rg@";
// Binaries shipped probes rely on, pinned at build time so r.run works
// whatever the jail's PATH holds. Anything else resolves via PATH.
const TOOLS = { "ast-grep": AST_GREP, rg: RG };
const USER_DIR = path.join(homedir(), "scratch", "jev-probes"); // probes at the root, harnesses/ and langs/ below
const DIRS = {
  probe: [[path.join(SHARE, "probes"), "shipped"], [USER_DIR, "user"]],
  harness: [[path.join(SHARE, "harnesses"), "shipped"], [path.join(USER_DIR, "harnesses"), "user"]],
  lang: [[path.join(SHARE, "langs"), "shipped"], [path.join(USER_DIR, "langs"), "user"]],
  // Shipped hooks are templates: only the user dir runs (opt in = file present).
  hookTemplates: [[path.join(SHARE, "hooks"), "shipped"]],
  hook: [[path.join(USER_DIR, "hooks"), "user"]],
};

const CONCURRENCY = 8; // Jev requests in flight
const MAX_UNITS = 200; // units per call
const MAX_CALLS = 500; // default Jev request budget per call, shared by all probes
const MAX_DEPTH = 3; // r.probe() nesting
const PROBE_TIMEOUT = 60_000;
const ROUTE_MIN = 0.35; // routing noul needed to run a CODE probe (declarative ones are asked directly); low: a missed finding costs more than a probe run
const MAX_POOL = 20000; // ponytail: neighbour candidates; a smarter index if repos outgrow it
const MAX_UNIT_LINES = 400; // longer units keep the changed region + exit lines (override: max_lines)
const FOLD_LINES = 60; // a changed container this small is reviewed whole, children folded in
const TOP_LINES = 80; // a run of changed lines outside any unit is split at this length
const NEIGHBOUR_LINES = 80;
const NEIGHBOURS = 2;
const HOOK_BUDGET = 12; // Jev requests shared by all hooks of one tool call
const HOOK_TIMEOUT = 20_000;
const MIN_SIM = 0.25; // low on purpose: a restyled copy shares names more than shape; similarity is shown to Jev
const GRAM = 5;
const STOP_GRAM = 500; // shape n-grams shared by more units than this carry no signal

const IE = "insufficient_evidence";
const NEGATIVE = new Set(["none", "ok", "consistent", "na", "n/a", "not_applicable", "no", "safe", "exact", "accurate", "guarded", "propagated"]);
const TEST_PATH = /(^|\/)(tests?|__tests__|benches)\/|[._-](test|spec)\.\w+$/;
// Files never worth a Jev call: lockfiles, generated declarations, minified bundles.
const SKIP_FILE =
  /(^|\/)(flake\.lock|Cargo\.lock|package-lock\.json|npm-shrinkwrap\.json|pnpm-lock\.yaml|yarn\.lock|bun\.lockb?|poetry\.lock|uv\.lock|Pipfile\.lock|go\.sum|Gemfile\.lock|composer\.lock|mix\.lock)$|\.d\.ts$|\.min\.(js|css)$/;
const SOPS = /ENC\[AES256_GCM,|^\+\s*"?sops"?:/m;
// Changed lines in a file with no lang: blank or punctuation only.
const TRIVIAL_ANY = /^[\s{}()[\];,]*$/;

// Default scope: no harness-specific framing.
const SCOPE =
  "Judge the lines of `unit` prefixed '+'; unprefixed lines are context. " +
  "`neighbours` (if any) are the most similar other units (with `similarity`, 0..1): context only, never under judgement.";

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

// ---- langs ------------------------------------------------------------------

// Lang modules (langs/*.mjs): `export const meta = { description, exts,
// grammar (ast-grep language, or a list), kinds: {unitKind: ast-grep rule},
// display?, trivial?: RegExp }`, optional `attach(u, lines)` /
// `isTest(u, all, lines)`. Shipped: rust, typescript.
export async function loadLangs(dirs = DIRS.lang) {
  const langs = new Map();
  for (const m of (await loadModules(dirs)).values()) langs.set(m.name, langFrom(m));
  return langs;
}
// {name, source, file, mod | error} -> lang (with `error` if malformed).
export async function loadLang(name, src, source, file) {
  const l = langFrom({ name, source, file, mod: await importSource(name, src) });
  if (l.error) throw new Error(l.error);
  return l;
}
function langFrom(m) {
  const meta = m.mod?.meta;
  const bad = m.error ?? (!Array.isArray(meta?.exts) ? "meta.exts must be a list of extensions" : typeof meta.kinds !== "object" || !meta.grammar ? "meta needs grammar and kinds" : null);
  return { name: m.name, source: m.source, file: m.file, meta: meta ?? {}, attach: m.mod?.attach, isTest: m.mod?.isTest, error: bad ?? undefined };
}
export const langOf = (langs, file) => {
  for (const l of langs.values()) if (!l.error && l.meta.exts.some((e) => file.endsWith(e))) return l;
  return null;
};
// The lang for `file`, or its extension when no lang module claims it (so a
// probe can whitelist "py" before anyone writes a python lang).
export const langName = (langs, file) => langOf(langs, file)?.name ?? (path.extname(file).slice(1) || path.basename(file));
const displayName = (langs, lang) => langs?.get(lang)?.meta?.display ?? lang;

// One ast-grep rule per (lang, grammar, kind); id "<lang>~<grammar>~<kind>".
const astRules = (langs) =>
  [...langs.values()]
    .filter((l) => !l.error)
    .flatMap((l) => [l.meta.grammar].flat().flatMap((g) => Object.entries(l.meta.kinds).map(([k, r]) => `id: ${l.name}~${g}~${k}\nlanguage: ${g}\nrule: ${r}`)))
    .join("\n---\n");

// Glob over repo-relative paths -> RegExp: `**/` any dirs, `*`/`?` within one.
// (Not path.matchesGlob: opencode loads plugins under bun.)
const GLOB_TOKEN = { "**/": "(?:.*/)?", "**": ".*", "*": "[^/]*", "?": "[^/]" };
export const globRe = (g) =>
  new RegExp("^" + g.split(/(\*\*\/|\*\*|\*|\?)/).map((t) => GLOB_TOKEN[t] ?? t.replace(/[.+^${}()|[\]\\]/g, "\\$&")).join("") + "$");

// Unified diff -> Map(file -> Set of added new-side line numbers). Lockfiles
// and generated files never count; `keep` filters further. Pure.
export function changedLines(diff, keep = () => true) {
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
      file = p !== "/dev/null" && !SKIP_FILE.test(p) && keep(p) ? p : null;
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
// "nothing to review": deleted, renamed without edits, removals only,
// binary, sops-encrypted, lockfiles/generated, `exclude`d. Pure.
export function unreviewedFiles(diff, exclude = () => false) {
  const out = [];
  for (const block of diff.split(/^(?=diff --git )/m)) {
    const m = /^diff --git a\/(.+?) b\/(.+)$/m.exec(block);
    if (!m) continue;
    const [, a, b] = m;
    const body = block.split(/^@@/m).slice(1).join("\n").split("\n");
    const adds = body.some((l) => l[0] === "+");
    const dels = body.some((l) => l[0] === "-");
    if (/^deleted file mode/m.test(block)) out.push(`deleted ${a}`);
    else if (/^Binary files /m.test(block)) out.push(`binary ${b}`);
    else if (/^rename from /m.test(block) && !adds) out.push(`renamed ${a}→${b}${dels ? " (lines removed)" : ""}`);
    else if (SKIP_FILE.test(b) || exclude(b)) out.push(b);
    else if (SOPS.test(block)) out.push(`sops-encrypted ${b}`);
    else if (!adds && dels) out.push(`removals only: ${b}`);
  }
  return out;
}

const run = (cmd, args, cwd, signal, timeout = 0) =>
  new Promise((resolve, reject) =>
    execFile(cmd, args, { cwd, signal, timeout, maxBuffer: 512 << 20 }, (err, stdout, stderr) =>
      err ? reject(new Error(String(stderr || err.message).trim())) : resolve(stdout)
    )
  );
const git = (cwd, args, signal) => run("git", args, cwd, signal);

// "pub fn foo(a: A) -> B {" -> "pub fn foo"; "impl X for Y {" -> "impl X for Y".
const unitName = (text) => text.split("\n")[0].split(/[({=]/)[0].trim().slice(0, 60);

// ast-grep --json=stream output -> units; kindOf(ruleId, file) -> [lang, kind].
const parseMatches = (out, kindOf) =>
  out
    .split("\n")
    .filter(Boolean)
    .flatMap((l) => {
      const m = JSON.parse(l);
      const file = m.file.replace(/^\.\//, "");
      if (SKIP_FILE.test(file)) return [];
      const [lang, kind] = kindOf(m.ruleId, file);
      return [{ file, lang, kind, start: m.range.start.line + 1, end: m.range.end.line + 1, text: m.text, name: unitName(m.text) }];
    });

// Every lang unit under `paths` of the tree at `dir` (respects .gitignore).
export async function scanUnits(dir, signal, langs, paths = ["."]) {
  langs ??= await loadLangs();
  const rules = astRules(langs);
  if (!rules) return [];
  const out = await run(AST_GREP, ["scan", "--inline-rules", rules, "--json=stream", ...paths], dir, signal);
  return parseMatches(out, (id) => {
    const [lang, , kind] = id.split("~");
    return [lang, kind];
  });
}

// Ad-hoc ast-grep (harness helper): `rules` maps an ast-grep language to a
// rule (YAML/JSON string or object); every match becomes a unit of `kind`.
// Node kinds differ per grammar (rust: line_comment/block_comment; most
// others: comment) and one unknown kind fails the whole scan.
export async function astGrep(dir, paths, rules, { kind = "match", signal } = {}) {
  const text = Object.entries(rules)
    .map(([g, r]) => `id: ${g}\nlanguage: ${g}\nrule: ${typeof r === "string" ? r : JSON.stringify(r)}`)
    .join("\n---\n");
  const out = await run(AST_GREP, ["scan", "--inline-rules", text, "--json=stream", ...[paths].flat()], dir, signal);
  return parseMatches(out, (id) => [id, kind]);
}

const innermost = (units, file, line) => {
  let best = null;
  for (const u of units) {
    if (u.file === file && u.start <= line && line <= u.end && (!best || u.end - u.start < best.end - best.start)) best = u;
  }
  return best;
};

// Lang hooks, applied when the unit's lang defines them. `attach` widens a
// unit with lines tree-sitter keeps outside it (Rust's #[...]); `isTest`
// recognises test code beyond TEST_PATH. `lines`: the unit's file.
export const withAttrs = (u, lines, langs) => langs?.get(u.lang)?.attach?.(u, lines) ?? u;
export function isTest(u, all, lines, langs) {
  if (TEST_PATH.test(u.file)) return true;
  return Boolean(langs?.get(u.lang)?.isTest?.(u, all, lines));
}

// Changed lines that are only imports/attributes/braces/comments aren't
// worth a call: the lang's `trivial`, else blank/punctuation.
const trivialFor = (langs, lang) => langs?.get(lang)?.meta?.trivial ?? TRIVIAL_ANY;
// Kind names with special meaning across langs: containers fold or drop
// (mods never fold), `top` is a run of changed lines outside any unit.
const CONTAINERS = new Set(["impl", "mod", "class"]);

// Changed lines -> units under review. Each line goes to its innermost unit;
// then containers (impl/class; mods never fold) are resolved:
//   * header changed and <= FOLD_LINES: reviewed whole as one unit (all
//     lines marked changed), its children dropped -- a new `impl Deref`
//     is judged as the impl, not as three fragments;
//   * otherwise the container is dropped when its own changed lines are only
//     header/braces/attributes (the children carry the change).
// Lines outside any unit (in files with no lang: all of them) become `top`
// pseudo-units (runs, gap <= 3, split every TOP_LINES), dropped when
// trivial. `fileLines` maps file -> its lines; `langs` supplies trivial/test
// hooks and names files no lang claims by extension.
export function changedUnits(units, changed, fileLines, langs) {
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
    const lang = langs ? langName(langs, file) : path.extname(file).slice(1);
    const trivial = trivialFor(langs, lang);
    const runs = [];
    for (const l of orphans) {
      const last = runs[runs.length - 1];
      if (last && l - last[last.length - 1] <= 3 && l - last[0] < TOP_LINES) last.push(l);
      else runs.push([l]);
    }
    for (const r of runs) {
      if (r.every((l) => trivial.test(src[l - 1] ?? ""))) continue;
      const start = Math.max(1, r[0] - 2);
      const end = Math.min(src.length, r[r.length - 1] + 2);
      const text = src.slice(start - 1, end).join("\n");
      out.push({ file, lang, kind: "top", start, end, text, name: "(top level)", changed: new Set(r) });
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
      if (own.every((t) => trivialFor(langs, c.lang).test(t) || isHeader(t, c))) drop.add(c);
    }
  }
  out = out.filter((u) => !drop.has(u));
  for (const u of out) u.test = isTest(u, units, fileLines.get(u.file), langs);
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

// ---- modules: probes, harnesses, langs ---------------------------------------

// Every module is an ES module (node: builtins only; it is imported from a
// content-addressed copy, so relative imports don't resolve). Loaded by
// content hash: an edited module takes effect on the next call.
const modules = new Map();
async function importSource(name, src) {
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
  try {
    return await modules.get(h);
  } catch (e) {
    modules.delete(h);
    throw e;
  }
}

// [[dir, source], ...] -> Map(name -> {name, source, file, mod} | {…, error});
// later dirs override earlier ones.
async function loadModules(dirs) {
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
        out.set(name, { name, source, file, mod: await importSource(name, await readFile(file, "utf8")) });
      } catch (e) {
        out.set(name, { name, source, file, error: e.message });
      }
    }
  }
  return out;
}

// What a module source is, from its exports: a harness exports `units`, a
// lang has `meta.exts`, a hook has `meta.tools`, anything else is a probe.
export async function moduleKind(name, src) {
  const mod = await importSource(name, src);
  return typeof mod.units === "function" ? "harness" : Array.isArray(mod.meta?.exts) ? "lang" : Array.isArray(mod.meta?.tools) ? "hook" : "probe";
}

// A probe:
//   export const meta = { description, langs?, kinds?, gate?, routable?, question? }
//   export default async function (unit, r) { return { p, label, note? } | null }
export async function loadProbe(name, src, source, file) {
  return probeFrom(name, await importSource(name, src), source, file);
}
function probeFrom(name, mod, source, file) {
  if (typeof mod.meta?.description !== "string") throw new Error("must `export const meta = { description: ... }`");
  const q = mod.meta.question;
  if (q !== undefined && typeof q !== "function" && (typeof q?.ask !== "string" || typeof q?.options !== "object"))
    throw new Error("meta.question must be { ask: string, options: {label: description} } or (unit, r) => that");
  if (typeof mod.default !== "function" && q === undefined)
    throw new Error("needs `meta.question` (declarative) or `export default async function (unit, r)` (code)");
  return { name, source, file, meta: mod.meta, fn: typeof mod.default === "function" ? mod.default : null };
}

// A probe's question for a unit, as a Jev choice.
const declQuestion = (p, u, r) => {
  const q = typeof p.meta.question === "function" ? p.meta.question(u, r) : p.meta.question;
  return choice(`${q.ask}\n${r.scope}`, q.options);
};

// Run any probe on a unit: declarative -> one cached choice; code -> its function.
async function evalProbe(p, u, r) {
  if (p.fn) return p.fn(u, r);
  const q = declQuestion(p, u, r);
  return toFinding(readAnswer((await r.ask({ q })).q, q.criteria));
}

// [[dir, source], ...] -> Map(name -> probe); later dirs override earlier ones.
// A probe that fails to load is kept with `error` so it shows up in listings.
export async function loadProbes(dirs = DIRS.probe) {
  const out = new Map();
  for (const m of (await loadModules(dirs)).values()) {
    try {
      if (m.error) throw new Error(m.error);
      out.set(m.name, probeFrom(m.name, m.mod, m.source, m.file));
    } catch (e) {
      out.set(m.name, { name: m.name, source: m.source, file: m.file, meta: {}, error: e.message });
    }
  }
  return out;
}

// A harness:
//   export const meta = { description, args?: {name: description}, neighbours?: bool }
//   export const scope = "how Jev should read `unit`"     (or (args) => string)
//   export async function units(args, h) -> { units, all?, header?, empty? }
//   export function state(unit, base, h)?                  (default: base)
function harnessFrom(name, mod, source, file) {
  if (typeof mod.meta?.description !== "string") throw new Error("must `export const meta = { description: ... }`");
  if (typeof mod.units !== "function") throw new Error("must `export async function units(args, h)`");
  return { name, source, file, meta: mod.meta, scope: mod.scope, units: mod.units, state: mod.state };
}
export async function loadHarness(name, src, source, file) {
  return harnessFrom(name, await importSource(name, src), source, file);
}
export async function loadHarnesses(dirs = DIRS.harness) {
  const out = new Map();
  for (const m of (await loadModules(dirs)).values()) {
    try {
      if (m.error) throw new Error(m.error);
      out.set(m.name, harnessFrom(m.name, m.mod, m.source, m.file));
    } catch (e) {
      out.set(m.name, { name: m.name, source: m.source, file: m.file, meta: {}, error: e.message });
    }
  }
  return out;
}

// The tag whitelist: a probe only ever sees units of its langs/kinds.
export const applies = (p, u) => !p.error && (!p.meta.langs || p.meta.langs.includes(u.lang)) && (!p.meta.kinds || p.meta.kinds.includes(u.kind));

// gate: RegExp, { <lang>: RegExp }, or (unit, r) => bool.
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

// Base Jev state for a unit: the unit plus (when the harness supplied a
// pool) its nearest same-kind neighbours; then the harness's `state` hook.
function unitState(rv, u) {
  const base = {
    lang: displayName(rv.langs, u.lang),
    kind: u.kind,
    unit_path: span(u),
    unit: render(u, rv.maxLines),
    ...(rv.pooled && {
      neighbours: rv.nearest(u).map((n) => ({
        path: span(n.unit),
        similarity: Number(n.sim.toFixed(2)),
        code: n.unit.text.split("\n").slice(0, NEIGHBOUR_LINES).join("\n"),
      })),
    }),
  };
  return rv.harness.state ? rv.harness.state(u, base, rv.h) : base;
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
    harness: rv.harness.name,
    scope: rv.scope,
    lang: unit.lang,
    langName: displayName(rv.langs, unit.lang),
    budget: rv.budget,
    render: (u = unit) => render(u, rv.maxLines),
    label: (u = unit) => label(u),
    changedText: (u = unit) => changedText(u),
    nearest: (u = unit) => rv.nearest(u),
    state: (extra = {}, u = unit) => ({ ...unitState(rv, u), ...extra }),
    ask: (questions, state = r.state()) => askCached(rv, state, questions),
    noul: async (question, state) => {
      const a = (await r.ask({ q: { type: "noul", instructions: `${question}\n${rv.scope}` } }, state)).q;
      if (!Number.isFinite(a?.noul)) throw new Error("malformed Jev noul answer");
      return a.noul;
    },
    choose: async (question, options, state) => {
      const q = choice(`${question}\n${rv.scope}`, options);
      return readAnswer((await r.ask({ q }, state)).q, q.criteria);
    },
    score: async (question, levels, state) =>
      (await r.ask({ q: { type: "score", instructions: `${question}\n${rv.scope}`, criteria: levels } }, state)).q,
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

const routeQuestion = (p, scope) => ({
  type: "noul",
  instructions:
    `Could the '+' lines plausibly have this problem: ${p.meta.description}? ` +
    "Answer yes only if they contain something where it could actually occur; this only decides whether to run a closer check.\n" +
    scope,
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
  for (const p of toRoute) qs[`route:${p.name}`] = routeQuestion(p, rv.scope);
  for (const [k, q] of Object.entries(rv.args.questions ?? {})) {
    qs[`ask:${k}`] = choice(`${q.ask}\n${rv.scope}`, q.options ?? { violated: "yes, the '+' lines have this problem", ok: "no, they do not", na: "the question does not apply here" });
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

// What a harness gets as `h`: the engine's building blocks, bound to this
// call's langs and abort signal. Paths are relative to `dir` arguments;
// `resolve` turns an agent-given path (relative to the session dir, ~ ok)
// into an absolute one.
function helpers({ directory, signal, langs, preset }) {
  return {
    directory,
    signal,
    langs,
    preset,
    resolve: (p = ".") => path.resolve(directory, p.replace(/^~(?=\/|$)/, homedir())),
    run: (cmd, argv = [], { cwd = directory, timeout = 0 } = {}) => run(TOOLS[cmd] ?? cmd, argv, cwd, signal, timeout),
    read: (file, dir = directory) => readFile(path.resolve(dir, file), "utf8"),
    // Files under `dir` (respects .gitignore; lockfiles/generated skipped),
    // repo-relative, filtered by globs.
    files: async (dir, globs = ["**"]) => {
      const out = await run(RG, ["--files"], dir, signal).catch(() => "");
      const res = [globs].flat().map(globRe);
      return out.split("\n").filter((f) => f && !SKIP_FILE.test(f) && res.some((re) => re.test(f))).sort();
    },
    glob: globRe,
    lang: (file) => langName(langs, file),
    unitName,
    scanUnits: (dir, paths) => scanUnits(dir, signal, langs, paths),
    astGrep: async (dir, paths, rules, opts) => (await astGrep(dir, paths, rules, { ...opts, signal })).map((u) => ({ ...u, lang: langName(langs, u.file) })),
    gitDiff: (a) => gitDiff(directory, { from: a.from, to: a.to, target: a.path }, signal),
    treeAt: (root, ref) => treeAt(root, ref, signal),
    changedLines,
    unreviewedFiles,
    selectUnits,
    changedUnits: (all, changed, fileLines) => changedUnits(all, changed, fileLines, langs),
    withAttrs: (u, lines) => withAttrs(u, lines, langs),
    isTest: (u, all, lines) => isTest(u, all, lines, langs),
  };
}

// One pass of `harness` over its units. `ask(state, questions, signal)` is
// the Jev call (injected so tests run offline); `cache` persists across
// calls; `probeDirs`/`langDirs` list libraries (later overrides earlier);
// `extraProbes` adds loaded probes (jev_probe's unsaved scripts); `preset`
// is handed to the harness as h.preset (tests feed the review harness a diff).
export async function runHarness(harness, args, opts) {
  const r = await evalHarness(harness, args, opts);
  return r.empty ?? [r.head, ...r.reviewed.slice(0, args.top ?? 20).map(formatLine)].join("\n");
}

// The same pass, structured: { head, reviewed: [{unit, results, score}] } worst
// first, or { empty }. `budget` (an object) may be shared across calls.
export async function evalHarness(harness, args, { directory, ask, cache, signal, probeDirs = DIRS.probe, langDirs = DIRS.lang, extraProbes = [], extraLangs = [], preset, budget }) {
  if (!harness) throw new Error("unknown harness (jev_probe list)");
  if (harness.error) throw new Error(`harness ${harness.name} failed to load: ${harness.error}`);
  const langs = await loadLangs(langDirs);
  for (const l of extraLangs) langs.set(l.name, l);
  const h = helpers({ directory, signal, langs, preset });
  const got = await harness.units(args, h);
  if (got?.empty) return { empty: got.empty, reviewed: [] };
  if (!Array.isArray(got?.units)) throw new Error(`harness ${harness.name}: units() must return { units: [...] }`);
  const dir = got.dir ?? directory;
  const all = got.all ?? got.units;

  const probes = await loadProbes(probeDirs);
  for (const p of extraProbes) probes.set(p.name, p);
  const targets = got.units.slice(0, MAX_UNITS);
  const pooled = Boolean(harness.meta.neighbours);
  const candidates = pooled ? all.filter((u) => u.end - u.start + 1 >= 3 && u.end - u.start < MAX_UNIT_LINES && !TEST_PATH.test(u.file)) : [];
  const rv = {
    args,
    harness,
    h,
    langs,
    scope: (typeof harness.scope === "function" ? harness.scope(args) : harness.scope) ?? SCOPE,
    root: got.root ?? dir,
    dir,
    all,
    signal,
    ask,
    cache,
    probes,
    pooled,
    maxLines: args.max_lines ?? MAX_UNIT_LINES,
    inflight: new Map(),
    limit: semaphore(CONCURRENCY),
    nearest: makeNearest(candidates.slice(0, MAX_POOL)),
    budget: budget ?? { left: args.budget ?? MAX_CALLS, used: 0, questions: 0 },
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
  const badLangs = [...langs.values()].filter((l) => l.error).map((l) => l.name);
  const budgetSkipped = reviewed.filter((r) => r.results.skipped).length;
  const bare = reviewed.filter((r) => !r.results.skipped && !Object.keys(r.results).length).length;
  const s = rv.stats;
  const head =
    (got.header ?? `${harness.name}: ${dir}`) +
    ` · ${targets.length} unit(s)` +
    (got.counts ?? []).map((c) => `, ${c}`).join("") +
    (bare ? `, ${bare} with no probes applied` : "") +
    ` · ${rv.budget.used} Jev request(s) / ${rv.budget.questions} question(s), budget left ${rv.budget.left}` +
    (budgetSkipped ? ` · ${budgetSkipped} unit(s) skipped: budget exhausted` : "") +
    ` · probes: ${s.direct} asked directly, ${s.run} code run(s)` +
    (s.candidates ? `, routed ${s.routed}/${s.candidates}` : "") +
    (s.gatedOut ? ` · ${s.gatedOut} forced probe×unit gated out` : "") +
    (s.depthHits ? ` · ${s.depthHits} r.probe call(s) cut at depth ${MAX_DEPTH}/cycle` : "") +
    (got.units.length > targets.length ? ` · capped, ${got.units.length - targets.length} unit(s) skipped` : "") +
    (candidates.length > MAX_POOL ? ` · neighbour search limited to ${MAX_POOL} units` : "") +
    (broken.length ? ` · probes failing to load: ${broken.join(", ")} (jev_probe list)` : "") +
    (badLangs.length ? ` · langs failing to load: ${badLangs.join(", ")}` : "") +
    (got.notes ?? []).map((n) => ` · ${n}`).join("");
  return { head, reviewed };
}

// The review harness over an already-computed diff (`dir`: the tree its new
// side lives in).
export async function runReview(args, { dir, root, diff, note, harnessDirs = DIRS.harness, ...rest }) {
  const harness = (await loadHarnesses(harnessDirs)).get("review");
  return runHarness(harness, args, { ...rest, directory: root, preset: { dir, root, diff, note } });
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

// ---- library (jev_probe) ----------------------------------------------------

// Save into the user library (one git repo at USER_DIR; harnesses/ and
// langs/ are subdirs of it). `sub`: "" | "harnesses" | "langs".
async function saveModule(sub, name, script, message) {
  const dir = path.join(USER_DIR, sub);
  await mkdir(dir, { recursive: true });
  try {
    await stat(path.join(USER_DIR, ".git"));
  } catch {
    await git(USER_DIR, ["init", "-q"]);
  }
  const rel = path.join(sub, `${name}.mjs`);
  await writeFile(path.join(USER_DIR, rel), script);
  try {
    await git(USER_DIR, ["add", "--", rel]);
    await git(USER_DIR, ["commit", "-q", "-m", message || `${sub ? sub.slice(0, -1) : "probe"} ${name}`]);
  } catch {
    // nothing to commit -- fine; the repo is a safety net, not a gate
  }
  return path.join(USER_DIR, rel);
}

const needleOf = (filter) => (typeof filter === "string" && filter !== "true" ? filter.toLowerCase() : null);

export async function listProbes(dirs = DIRS.probe, filter) {
  const probes = await loadProbes(dirs);
  const needle = needleOf(filter);
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

// probes + harnesses + langs, one section each.
export async function listLibrary(dirs = DIRS, filter) {
  const needle = needleOf(filter);
  const keep = (row) => !needle || row.toLowerCase().includes(needle);
  const hs = [...(await loadHarnesses(dirs.harness)).values()]
    .map((x) => `${x.name}\t${x.source}${x.meta.args ? `\targs: ${Object.keys(x.meta.args).join(",")}` : ""}\t${x.error ? `LOAD ERROR: ${x.error}` : x.meta.description}`)
    .filter(keep);
  const ls = [...(await loadLangs(dirs.lang)).values()]
    .map((x) => `${x.name}\t${x.source}\t${x.meta.exts?.join(",") ?? ""}${x.meta.kinds ? ` [${Object.keys(x.meta.kinds).join(",")}]` : ""}\t${x.error ? `LOAD ERROR: ${x.error}` : x.meta.description}`)
    .filter(keep);
  const ps = await listProbes(dirs.probe, filter);
  // Hooks: shipped templates + user (= on). A user copy that differs from its
  // template is marked, so a rebuilt template isn't silently stale.
  const tpls = dirs.hookTemplates ? await loadHooks(dirs.hookTemplates) : new Map();
  const users = dirs.hook ? await loadHooks(dirs.hook) : new Map();
  const ks = [];
  for (const name of [...new Set([...tpls.keys(), ...users.keys()])].sort()) {
    const u = users.get(name);
    const t = tpls.get(name);
    let state = u ? "on" : "off (jev_probe enable)";
    if (u && t && (await readFile(u.file, "utf8")) !== (await readFile(t.file, "utf8"))) state += ", differs from shipped";
    const x = u ?? t;
    const row = `${name}\t${t ? "shipped" : "user"}\t${state}\t${x.meta.tools?.join(",") ?? ""}${x.meta.files ? ` ${x.meta.files}` : ""}\t${x.error ? `LOAD ERROR: ${x.error}` : x.meta.description}`;
    if (keep(row)) ks.push(row);
  }
  return [
    `## harnesses\n${hs.join("\n") || "none"}`,
    `## langs (units by ast-grep; other files: changed-line hunks)\n${ls.join("\n") || "none"}`,
    `## probes\n${ps}`,
    ...(dirs.hook ? [`## hooks (after a tool call; only those in ~/scratch/jev-probes/hooks run)\n${ks.join("\n") || "none"}`] : []),
  ].join("\n\n");
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

// ---- hooks ------------------------------------------------------------------

// A hook: runs after matching tool calls; its text is appended to the result.
//   export const meta = { description, tools: ["edit", "write"], files?: RegExp }
//   export default async function (edit, h) -> string | null
// edit: { tool, file (absolute), rel (to the session dir), lines: [[s, e]] | null
// (null = whole file, i.e. write), added }. h: harness(name, args, engine) ->
// { head, reviewed: [{unit, results, score}] } | { empty } · line(result) ·
// ask(state, questions) · budget · signal · read(file) · directory. All hooks
// of one tool call share HOOK_BUDGET Jev requests and HOOK_TIMEOUT.
// Only hooks in ~/scratch/jev-probes/hooks run; shipped ones are templates
// (jev_probe enable). JEV_HOOKS=0 turns them all off.

function hookFrom(name, mod, source, file) {
  if (typeof mod.meta?.description !== "string") throw new Error("must `export const meta = { description: ... }`");
  if (!Array.isArray(mod.meta.tools)) throw new Error("meta.tools must list tool ids, e.g. [\"edit\", \"write\"]");
  if (typeof mod.default !== "function") throw new Error("needs `export default async function (edit, h)`");
  return { name, source, file, meta: mod.meta, fn: mod.default };
}
export async function loadHooks(dirs = DIRS.hook) {
  const out = new Map();
  for (const m of (await loadModules(dirs)).values()) {
    try {
      if (m.error) throw new Error(m.error);
      out.set(m.name, hookFrom(m.name, m.mod, m.source, m.file));
    } catch (e) {
      out.set(m.name, { name: m.name, source: m.source, file: m.file, meta: {}, error: e.message });
    }
  }
  return out;
}

// Line ranges of `needle` in `text` (1-based, inclusive).
export function rangesOf(text, needle) {
  const out = [];
  const span = needle.split("\n").length - 1;
  for (let i = text.indexOf(needle); i !== -1 && out.length < 50; i = text.indexOf(needle, i + needle.length)) {
    const start = text.slice(0, i).split("\n").length;
    out.push([start, start + span]);
  }
  return out;
}

// tool.execute.after input -> the edit a hook sees, or null (not an edit).
async function editOf(input, directory) {
  const a = input.args ?? {};
  const added = input.tool === "edit" ? a.newString : input.tool === "write" ? a.content : null;
  if (!a.filePath || typeof added !== "string" || !added) return null;
  const file = path.resolve(directory, a.filePath);
  let lines = null;
  if (input.tool === "edit") {
    lines = rangesOf(await readFile(file, "utf8"), added);
    if (!lines.length) return null;
  }
  return { tool: input.tool, file, rel: path.relative(directory, file), lines, added };
}

// Every matching hook, in parallel; joined output or null. Never throws.
export async function runHooks(input, { directory, ask, cache, signal, hookDirs = DIRS.hook, harnessDirs = DIRS.harness, ...rest }) {
  try {
    if (process.env.JEV_HOOKS === "0") return null;
    const hooks = [...(await loadHooks(hookDirs)).values()].filter(
      (k) => !k.error && k.meta.tools.includes(input.tool)
    );
    if (!hooks.length) return null;
    const edit = await editOf(input, directory);
    if (!edit) return null;
    const run = hooks.filter((k) => !k.meta.files || k.meta.files.test(edit.file));
    if (!run.length) return null;
    const sig = AbortSignal.any([signal, AbortSignal.timeout(HOOK_TIMEOUT)].filter(Boolean));
    const budget = { left: HOOK_BUDGET, used: 0, questions: 0 };
    const harnesses = await loadHarnesses(harnessDirs);
    const h = {
      directory,
      signal: sig,
      budget,
      read: (f) => readFile(path.resolve(directory, f), "utf8"),
      line: formatLine,
      ask: async (state, questions) => {
        if (budget.left <= 0) throw new BudgetError();
        budget.left--;
        budget.used++;
        return ask(state, questions, sig);
      },
      harness: (name, args, engine = {}) =>
        evalHarness(harnesses.get(name), { ...engine, ...args }, { directory, ask, cache, signal: sig, budget, ...rest }),
    };
    const outs = await Promise.all(
      run.map((k) =>
        Promise.race([k.fn(edit, h), new Promise((res) => sig.addEventListener("abort", () => res(null), { once: true }))]).catch(() => null)
      )
    );
    const text = outs.filter((o) => typeof o === "string" && o.trim());
    return text.length ? text.join("\n\n") : null;
  } catch {
    return null; // a failed hook must never cost the edit result
  }
}

// jev_probe enable: copy a shipped template into the user hooks dir.
async function enableHook(name) {
  const tpl = (await loadHooks(DIRS.hookTemplates)).get(name);
  if (!tpl) return `Error: no shipped hook ${name} (jev_probe list)`;
  if (tpl.error) return `Error: hook ${name} failed to load: ${tpl.error}`;
  return `Enabled hook ${name}: ${await saveModule("hooks", name, await readFile(tpl.file, "utf8"), `enable hook ${name}`)}`;
}

// ---- tools ------------------------------------------------------------------

const ENGINE_DOC = `- Probes: a library of small checks (list with jev_probe). Default pass, per unit: every probe whose langs/kinds fit and whose deterministic gate passes runs. Question-only probes are asked directly in ONE request per unit together with your \`questions\`; code probes are routed (Jev says whether they're plausible) or always run. \`probes: [names]\` runs exactly those instead.
- Your own \`questions\` (a choice per unit; default options violated/ok/na) go in the same request. Giving \`questions\` or \`probes\` turns routing off unless \`route: true\`. Spell out close alternatives as separate options (e.g. silent / logged / propagated) instead of yes/no -- in practice the most reliable signal you get. Options named none/ok/na/no/safe/… or prefixed \`ok_\` are not findings; \`minor_\` ones count half.
- Iterate: start broad, then narrow with \`units\`. Every answer is cached, so repeats only pay for new questions. A check you will want again belongs in a probe (jev_probe).
- Output: header, then \`path:start-end name<TAB>p<TAB>findings\`, worst first; p is the max over findings (\`rank_by\` picks one probe/question). p is a ranking signal, not calibrated; scores move ~±0.05 between identical runs. \`insufficient_evidence\` is an abstention, never a pass. Jev only classifies/scores: it ranks and labels units, it never writes text.`;

const REVIEW_DESCRIPTION = `Inspect changed code in a git diff with Jev, a fast decision model that answers typed questions. You steer: what to ask, where, and which probes run. ~1s per pass. Same as jev_run with harness "review".

- Units: each changed function/impl/struct/class/… in a language with a lang module (jev_probe list; shipped: rust, typescript; Rust units include their #[...] attributes), with '+' on changed lines and its 2 most similar existing units of the same kind as context. Changed lines outside any unit, and in files no lang claims (Nix, Python, shell, docs, …), become \`top\` units (runs of changed lines ±2). A small changed impl/class (header changed, <= ${FOLD_LINES} lines) is one unit; otherwise its changed children are the units (mods always split). Units over \`max_lines\` keep the changed region plus every return/error/status line. Test code (test paths; #[test], #[cfg(test)] mods) is skipped unless \`tests: true\` or picked explicitly. Deleted/renamed/removals-only/binary/sops-encrypted/lockfile/\`exclude\`d files are listed in the header as "not reviewed".
${ENGINE_DOC}
- \`path\` picks the repo (git runs from there; relative or ~). Refs resolve in THAT repo. Without \`to\`, compares \`from\` against the working tree. A \`from\` that isn't an ancestor (e.g. main after it moved on) is replaced by the merge-base; the header says so.`;

const RUN_DESCRIPTION = `Run Jev over any set of units a harness produces -- code review is just the shipped "review" harness (= jev_review). Use it for anything that is "for each X, classify/score/rank X": every comment under a dir by usefulness, every config block against rules, every fn in a crate for an audit, every doc section for staleness. ~1s per pass.

- \`harness\`: a saved one by name (jev_probe list), or \`script\` for an inline one (save with jev_probe name+script once it's worth keeping). \`args\` go to the harness (see its listed args); \`questions\`/\`probes\`/\`budget\`/\`top\`/\`rank_by\`/\`max_lines\` steer the engine as in jev_review.
- Writing a harness: see jev_probe's description (shape, \`h\` helpers, a worked comments example).
${ENGINE_DOC}`;

const PROBE_DESCRIPTION = `Manage the library jev_run/jev_review use: probes, harnesses and langs, plus edit hooks. Each is one ES module (node builtins only, no relative imports); the kind is inferred from its exports. Saved to ~/scratch/jev-probes/ (one git repo: probes at the root, harnesses/, langs/ and hooks/ below), overriding a shipped module of the same name.

Pick the smallest one that does the job:
- a PROBE when the units are right and you want a reusable check on them;
- a HARNESS when the units themselves are new (comments, config blocks, files, doc sections, anything not "changed code in a diff");
- a LANG when a language should get real units (fn/class/…) instead of changed-line hunks: it is data, ~10 lines.

## Probe -- ONE check on ONE unit
Question-only (preferred): asked directly, bundled into the unit's single Jev request.
\`\`\`js
export const meta = {
  description: "…",            // what it finds
  langs: ["rust"],              // whitelist of lang names (or file extensions for files no lang claims, e.g. "nix"); omit = all
  kinds: ["fn", "impl"],        // whitelist of unit kinds (lang kinds, "top", or whatever a harness emits); omit = all
  gate: /\\.unwrap\\(/,           // deterministic pre-filter: RegExp, {<lang>: RegExp}, or (unit, r) => bool
  gateOn: "changed",            // regex tests the '+' lines (default) or "unit" (whole unit: a small change can expose unchanged code)
  question: {                   // or (unit, r) => {ask, options}
    ask: "Question about the '+' lines?",
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
\`unit\`: {file, lang, kind, start, end, name, text, changed: Set<line>|null, test, …harness fields}. \`r\`: noul(q, state?) -> 0..1 · choose(q, options, state?) -> {choice, p, labels, abstain, probabilities} · score(q, levels, state?) · ask({id: question}, state?) raw · state(extra?, unit?) (default: the harness's state) · finding(chooseResult) · nearest(unit?) -> [{unit, sim}] · units (all) · render(unit?) · changedText(unit?) · label(unit?) · run(cmd, args, {timeout}) -> stdout, any binary, cwd = the tree · read(path) · probe(name, unit?) -> finding|null (recursion, depth <= ${MAX_DEPTH}, whitelists apply) · args · harness · scope · lang/langName · budget. All Jev calls are cached and count against one per-call budget.

## Harness -- WHAT the units are
\`\`\`js
export const meta = {
  description: "every comment under a path, with the code it annotates",
  args: { path: "dir to scan", glob: "files to include (default **)" },  // documents jev_run's \`args\`
  neighbours: false,            // true: each unit gets its 2 most similar units from \`all\` as context
};
// How Jev reads \`unit\` (appended to every question). String or (args) => string.
export const scope = "\`unit\` is one comment; lines prefixed '+' are the comment, the rest is the code below it.";

export async function units(args, h) {
  const dir = h.resolve(args.path);
  const files = await h.files(dir, args.glob ?? "**");
  // Comment node kinds differ per grammar: rust has line_comment/block_comment, most others \`comment\`.
  // One unknown kind fails the whole scan, so give each grammar its own rule.
  const found = await h.astGrep(dir, ".", {
    rust: { any: [{ kind: "line_comment" }, { kind: "block_comment" }] },
    typescript: { kind: "comment" }, tsx: { kind: "comment" }, javascript: { kind: "comment" },
    python: { kind: "comment" }, nix: { kind: "comment" }, bash: { kind: "comment" },
  }, { kind: "comment" });
  // Merge adjacent line comments into one block; show 3 lines of code below as context.
  const out = [];
  for (const c of found.filter((c) => files.includes(c.file)).sort((a, b) => a.file.localeCompare(b.file) || a.start - b.start)) {
    const prev = out[out.length - 1];
    if (prev && prev.file === c.file && c.start === prev.commentEnd + 1) { prev.commentEnd = c.end; continue; }
    out.push({ ...c, commentStart: c.start, commentEnd: c.end });
  }
  const units = [];
  for (const u of out) {
    const lines = (await h.read(u.file, dir)).split("\\n");
    const end = Math.min(lines.length, u.commentEnd + 3);
    const changed = new Set(Array.from({ length: u.commentEnd - u.commentStart + 1 }, (_, i) => u.commentStart + i));
    units.push({ ...u, end, text: lines.slice(u.start - 1, end).join("\\n"), name: lines[u.start - 1].trim().slice(0, 60), changed });
  }
  return { units, dir, header: \`comments: \${dir} (\${files.length} files)\` };
}
// optional: export function state(unit, base, h) { return { ...base, extra: … }; }
\`\`\`
Then: \`jev_run({ harness: "comments", args: { path: "X/Y/Z" }, questions: { useful: { ask: "<your criteria>", options: { useless: "restates the code", minor_stale: "…", ok_useful: "explains why" } } }, top: 50 })\`.
\`units(args, h)\` returns \`{ units, all?, dir?, root?, header?, counts?: [str], notes?: [str] }\` or \`{ empty: "message" }\`. A unit needs file, start, end, text; set \`kind\`, \`name\`, \`lang\` (h.lang(file)) and \`changed\` (Set of line numbers marked '+'; null = whole unit) as fits. Units are ranked worst first; \`top\` caps the listing, ${MAX_UNITS} units per call max.
\`h\`: resolve(path) (session-relative, ~ ok) · files(dir, globs) (rg --files: .gitignore'd, lockfiles skipped) · read(file, dir?) · run(cmd, args, {cwd, timeout}) · glob(pattern) -> RegExp · lang(file) · unitName(text) · scanUnits(dir, paths?) (every lang unit) · astGrep(dir, paths, {grammar: rule}, {kind}) · gitDiff({from, to, path}) -> {root, diff, note} · treeAt(root, ref) · changedLines(diff, keep?) · unreviewedFiles(diff, exclude?) · changedUnits(all, changed, fileLines) · selectUnits(all, units, selectors, skipTests) · withAttrs(u, lines) · isTest(u, all, lines) · langs · signal. The shipped \`review\` harness is the reference for a diff-based one.

## Lang -- how to split a language into units
\`\`\`js
export const meta = {
  description: "Python: fn, class",
  display: "Python",                         // shown to Jev
  exts: [".py"],
  grammar: "python",                         // ast-grep language (or a list, e.g. ["typescript", "tsx"])
  kinds: { fn: "{kind: function_definition}", class: "{kind: class_definition}" },  // unit kind -> ast-grep rule (YAML)
  trivial: /^\\s*(import\\s|from\\s|#|[()[\\],]*\\s*$)/,   // changed lines not worth a call on their own
};
// optional: export function attach(unit, fileLines) -> unit (widen, e.g. decorators); export function isTest(unit, all, fileLines) -> bool
\`\`\`
Kinds impl/class/mod are containers (a small changed one is reviewed whole; mods never fold); \`top\` is reserved for hunks outside any unit.

## Hook -- live feedback after an edit
Runs after matching tool calls; a non-empty return is appended to the tool result. Opt-in: only files in ~/scratch/jev-probes/hooks/ run (\`enable\` copies a shipped one there; delete to turn off). All hooks of one call share ${HOOK_BUDGET} Jev requests and ${HOOK_TIMEOUT / 1000}s; a failing hook is dropped.
\`\`\`js
export const meta = { description: "…", tools: ["edit", "write"], files: /\\.rs$/ };
export default async function (edit, h) {   // edit: {tool, file, rel, lines: [[s,e]] | null (write: whole file), added}
  const r = await h.harness("edited", { path: edit.file, lines: edit.lines }, { probes: ["rust-design"] });
  const hits = r.reviewed.filter((x) => x.score >= 0.85).slice(0, 3);
  return hits.length ? \`[my feedback]\\n\${hits.map(h.line).join("\\n")}\` : null;
}
\`\`\`
\`h\`: harness(name, args, engine) -> {head, reviewed: [{unit, results, score}]} | {empty} · line(result) · ask(state, questions) · read(file) · budget · signal · directory.

## Shapes
\`list\` (true or a filter) · \`enable: name\` turns on a shipped hook · \`name\` + \`script\` saves (git-committed), then dry-runs it if \`units\` is given (probes and langs; dry-run harnesses with jev_run) · \`script\` alone dry-runs an unsaved probe/lang (needs \`units\`) · \`name\` alone dry-runs a saved probe on \`units\`. Dry runs review a diff: same \`path\`/\`from\`/\`to\` as jev_review (default from=HEAD).`;

async function server(pctx) {
  const hookDir = pctx?.directory ?? process.cwd();
  const require = createRequire((process.env.HOME || "/root") + "/.config/opencode/package.json");
  const { z } = require("zod");
  const cache = new Map(); // ponytail: unbounded, per opencode process; an LRU if long sessions bloat it
  const rules = z.record(z.string(), z.string());
  const engine = {
    probes: z.array(z.string()).optional().describe("Run exactly these probes (by name) on every unit whose langs/kinds fit and whose gate passes; turns routing off unless route: true."),
    route: z.boolean().optional().describe("Let Jev route each unit to library probes. Default: on unless questions/probes are given."),
    questions: z
      .record(
        z.string(),
        z.object({
          ask: z.string().describe("The question, about the unit's '+' lines"),
          options: rules.optional().describe("{label: description}. Name the no-problem options none/ok/na (or ok_*). Default: violated/ok/na."),
        })
      )
      .optional()
      .describe("Your own questions for this pass, keyed by name."),
    criteria: z
      .record(z.string(), rules)
      .optional()
      .describe("Named style rules {rule-name: description} per lang name (or `all`); runs the `rules` probe with them."),
    rank_by: z.string().optional().describe("Rank by this one probe/question instead of the max over all."),
    budget: z.number().int().positive().optional().describe(`Max Jev requests for this call (default ${MAX_CALLS}); one request carries all of a unit's questions.`),
    max_lines: z
      .number()
      .int()
      .positive()
      .optional()
      .describe(`Units longer than this are shown as the '+' region +-20 lines plus every return/error/status line (default ${MAX_UNIT_LINES}).`),
    top: z.number().int().positive().optional().describe("How many units to list (default 20)"),
  };
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

  const go = async (harness, args, ctx, extra = {}) =>
    runHarness(harness, args, { directory: ctx.directory, ask: jevAsk, cache, signal: ctx.abort, ...extra });
  const review = async (args, ctx, extra) => go((await loadHarnesses()).get("review"), args, ctx, extra);
  const NAME = /^[a-z0-9][a-z0-9-]*$/;

  return {
    "tool.execute.after": async (input, output) => {
      const note = await runHooks(input, { directory: hookDir, ask: jevAsk, cache });
      if (note) output.output = `${output.output ?? ""}\n\n${note}`;
    },
    tool: {
      jev_run: {
        description: RUN_DESCRIPTION,
        args: {
          harness: z.string().optional().describe("Saved harness name (jev_probe list)."),
          script: z.string().optional().describe("Inline harness module source (unsaved), instead of `harness`."),
          args: z.record(z.string(), z.any()).optional().describe("Arguments for the harness (its listed args)."),
          ...engine,
        },
        async execute(a, ctx) {
          try {
            const harness = a.script ? await loadHarness("inline", a.script, "inline") : a.harness ? (await loadHarnesses()).get(a.harness) : null;
            if (!harness) return a.harness ? `Error: unknown harness ${a.harness} (jev_probe list)` : "Error: give `harness` or `script`.";
            const { harness: _h, script: _s, args: hargs, ...rest } = a;
            return { title: harness.name, output: await go(harness, { ...hargs, ...rest }, ctx) };
          } catch (e) {
            return `Error: ${e.message}`;
          }
        },
      },
      jev_review: {
        description: REVIEW_DESCRIPTION,
        args: {
          ...where,
          ...engine,
          tests: z.boolean().optional().describe("Include test code (default: skipped)."),
          exclude: z.array(z.string()).optional().describe("Globs of files to leave out (e.g. **/*.md); listed as not reviewed."),
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
          list: z.union([z.boolean(), z.string()]).optional().describe("List harnesses, langs, probes and hooks (true) or filter by substring."),
          name: z.string().optional().describe("Module name ([a-z0-9-]). With script: save. Alone: dry-run the saved probe."),
          script: z.string().optional().describe("Module source: a probe, harness, lang or hook (inferred from its exports)."),
          enable: z.string().optional().describe("Turn on a shipped hook: copies it to ~/scratch/jev-probes/hooks/ (delete the file to turn it off)."),
          message: z.string().optional().describe("Git commit message for a save."),
          ...where,
          from: where.from.optional(),
        },
        async execute(args, ctx) {
          try {
            if (args.list && args.list !== "false") return await listLibrary(DIRS, args.list);
            if (args.enable) return await enableHook(args.enable);
            if (args.name && !NAME.test(args.name)) return "Error: name must match [a-z0-9][a-z0-9-]*";
            const name = args.name ?? "inline";
            let extra = {};
            let saved = "";
            let kind = "probe";
            if (args.script) {
              kind = await moduleKind(name, args.script);
              const source = args.name ? "user" : "inline";
              if (kind === "hook") {
                hookFrom(name, await importSource(name, args.script), source);
                return args.name ? `Saved hook ${name} to ${await saveModule("hooks", name, args.script, args.message)} (active from the next edit).` : "Hook loads; save it with a name to turn it on.";
              }
              const loaded = await { probe: loadProbe, harness: loadHarness, lang: loadLang }[kind](name, args.script, source);
              if (args.name) saved = `Saved ${kind} ${name} to ${await saveModule({ probe: "", harness: "harnesses", lang: "langs" }[kind], name, args.script, args.message)}.`;
              if (kind === "harness") return saved || `Harness loads (${loaded.meta.description}); run it with jev_run({ script, args }).`;
              if (!args.name) extra = kind === "lang" ? { extraLangs: [loaded] } : { extraProbes: [loaded] };
            } else if (!args.name) return "Error: give list, name, or script.";
            if (!args.units?.length) return saved || "Error: dry runs need `units`.";
            const dry = { from: args.from ?? "HEAD", to: args.to, path: args.path, units: args.units, tests: true, ungated: true };
            // A lang dry run: the units it now produces, with no Jev questions.
            const out = await review(kind === "lang" ? { ...dry, probes: [], route: false } : { ...dry, probes: [name], route: false }, ctx, extra);
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


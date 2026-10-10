import { test } from "node:test";
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { mkdtempSync, mkdirSync, writeFileSync, appendFileSync, readFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import {
  changedLines,
  readAnswer,
  features,
  makeNearest,
  selectUnits,
  changedUnits,
  render,
  changedText,
  isTest,
  withAttrs,
  unreviewedFiles,
  loadProbes,
  listProbes,
  listLibrary,
  loadLangs,
  loadHarness,
  moduleKind,
  globRe,
  applies,
  gitDiff,
  runReview,
  runHarness,
  runHooks,
  loadHarnesses,
} from "./opencode-plugin.js";

const SHIPPED = fileURLToPath(new URL("./probes", import.meta.url));
const LANG_DIRS = [[fileURLToPath(new URL("./langs", import.meta.url)), "shipped"]];
const HARNESS_DIRS = [[fileURLToPath(new URL("./harnesses", import.meta.url)), "shipped"]];
const LANGS = await loadLangs(LANG_DIRS);
// Hermetic: shipped langs/harnesses only, whatever ~/scratch/jev-probes holds.
const review = (args, opts) => runReview(args, { langDirs: LANG_DIRS, harnessDirs: HARNESS_DIRS, ...opts });
const g = (cwd, ...a) =>
  execFileSync("git", ["-c", "user.name=t", "-c", "user.email=t@t", "-c", "init.defaultBranch=main", ...a], { cwd });

const EXISTING = `pub fn migrate_user(client: &Client, cfg: &Config) -> Result<(), Error> {
    let orgs = discover(client, cfg)?;
    let items: Vec<MigrateOrganization> = orgs.iter().map(|o| MigrateOrganization::new(o, InstallScope::User)).collect();
    submit(client, &items)?;
    log::info!("migrated {} orgs", items.len());
    Ok(())
}
`;
const COPY = `
pub fn migrate_system(client: &Client, cfg: &Config) -> Result<(), Error> {
    let orgs = discover(client, cfg).unwrap();
    let items: Vec<MigrateOrganization> = orgs.iter().map(|o| MigrateOrganization::new(o, InstallScope::System)).collect();
    submit(client, &items)?;
    log::info!("migrated {} orgs", items.len());
    Ok(())
}

pub fn scope_or_default(s: Option<InstallScope>) -> InstallScope {
    let scope = s.unwrap_or(InstallScope::User);
    scope
}

#[cfg(test)]
mod tests {
    #[test]
    fn it_works() {
        assert_eq!(super::thing().unwrap(), 1);
    }
}
`;

// outer (no commits) / inner repo. src/m.rs: existing fn + a new near copy
// (with .unwrap()), a new fn using only unwrap_or, a new test mod.
// src/other.rs: unrelated, gets a trivial `use`. web/app.tsx: new component.
function fixture() {
  const outer = mkdtempSync(join(tmpdir(), "jr-"));
  const inner = join(outer, "inner");
  mkdirSync(join(inner, "src"), { recursive: true });
  mkdirSync(join(inner, "web"), { recursive: true });
  g(outer, "init", "-q");
  g(inner, "init", "-q");
  writeFileSync(join(inner, "src/m.rs"), "use std::fmt;\n\n" + EXISTING);
  writeFileSync(join(inner, "src/other.rs"), "pub struct Point {\n    x: f64,\n    y: f64,\n}\n");
  writeFileSync(join(inner, "web/app.tsx"), "export const Old = () => <p />;\n");
  g(inner, "add", ".");
  g(inner, "commit", "-qm", "i");
  appendFileSync(join(inner, "src/m.rs"), COPY);
  appendFileSync(join(inner, "src/other.rs"), "use std::io;\n");
  appendFileSync(join(inner, "web/app.tsx"), "export function App(props: any) {\n  let x = props.a == 1;\n  return <div>{x}</div>;\n}\n");
  return { outer, inner };
}

// Jev stand-in. noul -> route(instructions) (default 0.9); choice -> the
// first option, or pick(instructions, options) if it returns one.
function fakeJev({ route = () => 0.9, pick = () => null } = {}) {
  const calls = [];
  const ask = async (state, questions) => {
    calls.push({ state, questions });
    const answers = {};
    for (const [k, q] of Object.entries(questions)) {
      if (q.type === "noul") answers[k] = { type: "noul", noul: route(q.instructions, state) };
      else {
        const opts = Object.keys(q.criteria);
        const c = pick(q.instructions, opts, state) ?? opts[0];
        answers[k] = { type: "choice", choice: c, probabilities: Object.fromEntries(opts.map((o) => [o, o === c ? 0.8 : 0.2 / (opts.length - 1)])) };
      }
    }
    return { answers };
  };
  return { ask, calls };
}

async function setup(jevOpts, extraDirs = []) {
  const { inner } = fixture();
  const { root, diff } = await gitDiff(inner, { from: "HEAD" });
  const jev = fakeJev(jevOpts);
  const cache = new Map();
  const go = (args, extra = {}) =>
    review({ from: "HEAD", ...args }, { dir: root, root, diff, ask: jev.ask, cache, probeDirs: [[SHIPPED, "shipped"], ...extraDirs], ...extra });
  return { inner, root, diff, jev, go };
}

const lineFor = (out, prefix) => out.split("\n").find((l) => l.startsWith(prefix));

test("changedLines: added new-side lines per supported file", () => {
  const diff = `diff --git a/a.rs b/a.rs
--- a/a.rs
+++ b/a.rs
@@ -1,3 +1,4 @@
 one
-two
+TWO
+three
 four
diff --git a/x.d.ts b/x.d.ts
--- a/x.d.ts
+++ b/x.d.ts
@@ -0,0 +1 @@
+declare const x: 1;
`;
  assert.deepEqual([...changedLines(diff)].map(([f, s]) => [f, [...s]]), [["a.rs", [2, 3]]]);
});

test("readAnswer: p sums findings; na/none/ok are not findings; abstention flagged", () => {
  const opts = { a: "", b: "", none: "", na: "", insufficient_evidence: "" };
  const r = readAnswer({ choice: "a", probabilities: { a: 0.5, b: 0.2, none: 0.1, na: 0.15, insufficient_evidence: 0.05 } }, opts);
  assert.ok(Math.abs(r.p - 0.7) < 1e-9);
  assert.deepEqual(r.labels, [["a", 0.5], ["b", 0.2]]);
  assert.equal(readAnswer({ choice: "na", probabilities: { na: 0.9, a: 0.1 } }, opts).p, 0.1);
  assert.equal(readAnswer({ choice: "insufficient_evidence", probabilities: { insufficient_evidence: 1 } }, opts).abstain, true);
  assert.throws(() => readAnswer({ choice: "zzz", probabilities: {} }, opts));
  // ok_* never counts; minor_* counts half
  const o2 = { bad: "", minor_vague: "", ok_invariant: "", insufficient_evidence: "" };
  const r2 = readAnswer({ choice: "ok_invariant", probabilities: { bad: 0.2, minor_vague: 0.4, ok_invariant: 0.4 } }, o2);
  assert.ok(Math.abs(r2.p - 0.4) < 1e-9, `p ${r2.p}`);
  assert.deepEqual(r2.labels, [["bad", 0.2], ["minor_vague", 0.2]]);
});

test("nearest: renamed near-copy found; other kinds never paired", () => {
  const unit = (file, start, kind, text) => ({ file, start, kind, end: start + text.split("\n").length - 1, text });
  const target = unit("m.rs", 10, "fn", COPY.trim().split("\n\n")[0]);
  const fnTwin = unit("m.rs", 1, "fn", EXISTING.trim());
  const sameTextOtherKind = unit("x.rs", 1, "type", EXISTING.trim());
  const [pick, ...rest] = makeNearest([fnTwin, sameTextOtherKind, target])(target);
  assert.equal(pick.unit, fnTwin);
  assert.ok(pick.sim > 0.6, `sim ${pick.sim}`);
  assert.deepEqual(rest, []);
  assert.deepEqual(features("fn a(x: u8) {}").grams, features("fn b(y: u8) {}").grams);
});

test("render/changedText; selectUnits by line, prefix, unchanged; tests skipped unless explicit", () => {
  const u = { file: "a.rs", start: 5, end: 7, text: "fn a() {\n  x();\n}", changed: new Set([6]) };
  assert.equal(render(u), "  fn a() {\n+   x();\n  }");
  assert.equal(changedText(u), "  x();");
  assert.equal(render({ ...u, changed: null }), "+ fn a() {\n+   x();\n+ }");
  const t = { ...u, file: "a.rs", start: 9, end: 9, test: true };
  const other = { file: "b.rs", start: 1, end: 3, text: "fn b() {}", name: "fn b" };
  assert.deepEqual(selectUnits([u, t, other], [u, t]).units, [u]);
  assert.deepEqual(selectUnits([u, t, other], [u, t], null, false).units, [u, t]);
  const r = selectUnits([u, t, other], [u, t], ["a.rs:6-7 fn a", "a.rs:9", "b.rs:2", "zz/"]);
  assert.deepEqual(r.units.slice(0, 2), [u, t]);
  assert.equal(r.units[2].changed, null);
  assert.deepEqual(r.unmatched, ["zz/"]);
});

test("isTest: path, #[test], #[cfg(test)] mod", () => {
  const lines = ["#[cfg(test)]", "mod tests {", "    #[test]", "    fn t() {}", "}", "fn real() {}"];
  const mod = { file: "a.rs", lang: "rust", kind: "mod", start: 2, end: 5 };
  const inMod = { file: "a.rs", lang: "rust", kind: "fn", start: 4, end: 4 };
  const real = { file: "a.rs", lang: "rust", kind: "fn", start: 6, end: 6 };
  assert.equal(isTest(inMod, [mod], lines, LANGS), true);
  assert.equal(isTest(mod, [mod], lines, LANGS), true);
  assert.equal(isTest(real, [mod], lines, LANGS), false);
  assert.equal(isTest({ file: "web/x.spec.ts", lang: "typescript" }, [], null, LANGS), true);
  assert.equal(isTest({ file: "tests/it.rs", lang: "rust" }, [], null, LANGS), true);
  assert.equal(isTest({ file: "pkg/foo_test.py", lang: "py" }, [], null, LANGS), true); // any language by path
});

test("shipped probes load; whitelists and gates are deterministic", async () => {
  const probes = await loadProbes([[SHIPPED, "shipped"]]);
  for (const p of probes.values()) assert.equal(p.error, undefined, `${p.name}: ${p.error}`);
  assert.deepEqual(
    [...probes.keys()].sort(),
    ["comment-quality", "conventions", "misattributed-error", "overbroad-match", "panic", "reentrant-caller", "reentry-side-effect", "rules", "rust-design", "secret-debug", "swallowed-error"]
  );
  // Question-only probes have no fn; code probes do.
  assert.equal(probes.get("panic").fn, null);
  assert.equal(typeof probes.get("reentrant-caller").fn, "function");
  const panic = probes.get("panic");
  assert.equal(applies(panic, { lang: "typescript", kind: "fn" }), false);
  assert.equal(applies(panic, { lang: "rust", kind: "fn" }), true);
  assert.equal(applies(panic, { lang: "rust", kind: "type" }), false);
  const r = { changedText: (u) => u.text };
  const gate = (text, test = false) => panic.meta.gate({ text, test }, r);
  assert.equal(gate("let x = s.unwrap_or(1);"), false);
  assert.equal(gate("let x = s.unwrap_or_default();"), false);
  assert.equal(gate("let x = s.unwrap();"), true);
  assert.equal(gate('let x = s.expect("no");'), true);
  assert.equal(gate("let x = s.unwrap();", true), false); // test units never
  // reentry: one-shot wrappers don't pass the gate, state loops do -- on the whole unit.
  const reentry = probes.get("reentry-side-effect").meta;
  assert.equal(reentry.gateOn, "unit");
  const re = reentry.gate.rust;
  assert.equal(re.test("pub fn submit_migrate(c: &Client) -> Result<()> { c.post(url).send()?; Ok(()) }"), false);
  assert.equal(re.test("loop { match state { State::Initialized => try_auto_migrate(&c) } }"), true);
  // secret-debug: derive(Debug) on a struct, attributes now part of the unit
  const sd = probes.get("secret-debug").meta.gate;
  assert.equal(sd.test("#[derive(\n    Debug,\n    Clone,\n)]\npub struct C {\n    password: String,\n}"), true);
  assert.equal(sd.test("#[derive(Clone)]\n#[serde(rename_all = \"camelCase\")]\npub struct C {}"), false);
  assert.equal(sd.test("#[derive(Debug)]\npub enum E { A }"), false);
});

test("runReview: question-only probes bundled in one request; code probes routed; tests skipped", async () => {
  const { go, jev } = await setup({ route: () => 0.1 });
  const out = await go({});
  const [head] = out.split("\n");
  // The #[cfg(test)] mod is split (mods never fold): its fn is a test unit, skipped.
  assert.match(head, /3 unit\(s\), 1 test unit\(s\) skipped/);
  assert.ok(!out.includes("other.rs"), out);

  const copy = lineFor(out, "src/m.rs:11-17 pub fn migrate_system\t");
  assert.ok(copy, out);
  assert.match(copy, /panic: panics 0\.80/); // ok_invariant/none don't add to p
  assert.match(copy, /conventions: duplicates 0\.83 ≈ src\/m\.rs:3-9 pub fn migrate_user \(sim 0\.\d\d\)/); // + minor_deviates at half

  // One request per unit: no routing question for question-only probes.
  const copyCalls = jev.calls.filter((c) => c.state.unit_path === "src/m.rs:11-17");
  const first = copyCalls[0];
  assert.ok(Object.values(first.questions).some((q) => q.instructions.includes("unwrap()/.expect()")), "panic asked directly");
  assert.ok(!Object.values(first.questions).some((q) => q.type === "noul" && q.instructions.includes("unwrap/expect/index/panic")));

  // unwrap_or only: panic gate fails, so panic is never asked for it.
  const calls = jev.calls.filter((c) => c.state.unit_path === "src/m.rs:19-22");
  const asked = calls.flatMap((c) => Object.values(c.questions).map((q) => q.instructions)).join("\n");
  assert.ok(!asked.includes("unwrap()/.expect()"), asked);

  // TS unit: never offered the rust-only panic probe.
  const ts = jev.calls.filter((c) => c.state.unit_path.startsWith("web/"));
  assert.ok(!ts.flatMap((c) => Object.values(c.questions)).some((q) => q.instructions.includes("unwrap()/.expect()")));
});

test("runReview: questions, rank_by, forced probes, cache, explicit test unit", async () => {
  const { go, jev } = await setup({ pick: (ins, opts) => (ins.includes("Is it async") ? "na" : null) });
  const out = await go({ questions: { asyncq: { ask: "Is it async?" }, risky: { ask: "Risky?" } }, rank_by: "asyncq" });
  assert.match(out.split("\n")[0], /probes: 0 asked directly, 0 code run/); // questions given -> routing off
  assert.match(out, /ok: asyncq/); // na is not a finding
  assert.match(out, /risky: violated 0\.80/);
  assert.match(lineFor(out, "src/m.rs:11-17") ?? "", /\t0\.00\t/); // ranked by asyncq only

  const n = jev.calls.length;
  await go({ questions: { asyncq: { ask: "Is it async?" }, risky: { ask: "Risky?" } } });
  assert.equal(jev.calls.length, n, "second identical pass is fully cached");

  const forced = await go({ probes: ["panic"], units: ["src/m.rs:13", "src/m.rs:28"] });
  assert.match(lineFor(forced, "src/m.rs:11-17") ?? "", /panic: panics/);
  // explicit pick inside the test mod: the test fn (with its #[test]) is the unit; panic gates out test code
  assert.match(lineFor(forced, "src/m.rs:26-29 fn it_works\t") ?? forced, /\tno probes applied$/);
  assert.match(forced.split("\n")[0], /1 forced probe×unit gated out/);
});

test("probes: user override, recursion depth cap, cycles, broken probe listed", async () => {
  const user = mkdtempSync(join(tmpdir(), "jp-"));
  writeFileSync(
    join(user, "panic.mjs"),
    `export const meta = { description: "user panic", langs: ["rust"], routable: false };
     export default async (u) => ({ p: 0.42, label: "user-override" });`
  );
  writeFileSync(
    join(user, "deep.mjs"),
    `export const meta = { description: "recurses", routable: false };
     export default async (u, r) => { const below = await r.probe("deep"); return { p: 0.5, label: "d" + r.depth, note: below ? below.label : "cut" }; };`
  );
  writeFileSync(
    join(user, "chain.mjs"),
    `export const meta = { description: "chains", routable: false };
     export default async (u, r) => { const n = await r.probe("chain2"); return n && { p: n.p, label: "chain", note: n.label + " via depth " + r.depth }; };`
  );
  writeFileSync(
    join(user, "chain2.mjs"),
    `export const meta = { description: "leaf", routable: false };
     export default async (u, r) => ({ p: 0.6, label: "leaf" + r.depth });`
  );
  writeFileSync(join(user, "broken.mjs"), `export const meta = {};`);

  const listing = await listProbes([[SHIPPED, "shipped"], [user, "user"]]);
  assert.match(listing, /^panic\tuser\t/m);
  assert.match(listing, /^broken\tuser\t.*LOAD ERROR/m);

  const { go } = await setup({}, [[user, "user"]]);
  const out = await go({ probes: ["panic", "deep", "chain", "broken"], units: ["src/m.rs:13"] });
  const line = lineFor(out, "src/m.rs:11-17");
  assert.match(line, /panic: user-override 0\.42/);
  assert.match(line, /deep: d0 0\.50 cut/); // r.probe("deep") from deep is a cycle -> null
  assert.match(line, /chain: chain 0\.60 leaf1 via depth 0/); // chain (depth 0) -> chain2 (depth 1)
  assert.match(line, /broken: error failed to load/);
  assert.match(out.split("\n")[0], /probes failing to load: broken/);
});

test("probes: depth cap stops a non-cyclic chain at MAX_DEPTH", async () => {
  const user = mkdtempSync(join(tmpdir(), "jp-"));
  for (let i = 0; i < 6; i++) {
    writeFileSync(
      join(user, `p${i}.mjs`),
      `export const meta = { description: "level ${i}", routable: false };
       export default async (u, r) => { const n = await r.probe("p${i + 1}"); return { p: 0.5, label: n ? n.label : "stop${i}" }; };`
    );
  }
  writeFileSync(join(user, "p6.mjs"), `export const meta = { description: "end", routable: false }; export default async () => ({ p: 1, label: "end" });`);
  const { go } = await setup({}, [[user, "user"]]);
  const out = await go({ probes: ["p0"], units: ["src/m.rs:13"] });
  assert.match(lineFor(out, "src/m.rs:11-17"), /p0: stop3 0\.50/); // p0 -> p1 -> p2 -> p3, then cut
  assert.match(out.split("\n")[0], /r\.probe call\(s\) cut at depth 3/);
});

test("budget: exhausted budget -> one skipped line per unit and a header count, no error spam", async () => {
  const { go } = await setup({});
  const out = await go({ questions: { q: { ask: "x?" } }, budget: 1 });
  const lines = out.split("\n");
  assert.match(lines[0], /1 Jev request\(s\) \/ 1 question\(s\), budget left 0 · 2 unit\(s\) skipped: budget exhausted/);
  assert.equal(lines.filter((l) => l.endsWith("\tskipped (budget)")).length, 2);
  assert.ok(!out.includes("error"), out);
});

test("render: long unit keeps changed region and every exit line, e.g. a 401 far below", () => {
  const body = [];
  body.push("pub fn migrate(req: Req) -> Response {");
  for (let i = 0; i < 30; i++) body.push(`    let a${i} = step${i}(&req);`);
  body.push("    for org in orgs {");
  body.push("        if !KNOWN.contains(&org.kind) { continue; }"); // the change, line 33
  body.push("    }");
  for (let i = 0; i < 150; i++) body.push(`    let b${i} = more${i}(&req);`);
  body.push('    if verified == 0 { return Response::status(401, "no organization credentials verified"); }');
  for (let i = 0; i < 10; i++) body.push(`    let c${i} = tail${i}();`);
  body.push("    Response::ok()");
  body.push("}");
  const u = { file: "m.rs", start: 1, end: body.length, text: body.join("\n"), changed: new Set([33]) };
  const out = render(u, 100);
  assert.ok(out.includes("no organization credentials verified"), "the 401 survives clipping");
  assert.ok(out.includes("+         if !KNOWN.contains(&org.kind) { continue; }"));
  assert.match(out, /… \(\d+ lines\)/);
  assert.ok(out.split("\n").length < 80, `clipped to ${out.split("\n").length} lines`);
  assert.equal(render(u, 1000).split("\n").length, body.length); // under the limit: whole
});

test("changedUnits: small changed container folds; header-only parent dropped", () => {
  const lines = [
    "struct Name(String);", // 1
    "impl Deref for Name {", // 2
    "    type Target = str;", // 3
    "    fn deref(&self) -> &str {", // 4
    "        &self.0", // 5
    "    }", // 6
    "}", // 7
    "impl Big {", // 8
    "    fn a(&self) {", // 9
    "        x();", // 10
    "    }", // 11
    "}", // 12
  ];
  const text = (a, b) => lines.slice(a - 1, b).join("\n");
  const all = [
    { file: "a.rs", lang: "rust", kind: "impl", start: 2, end: 7, text: text(2, 7), name: "impl Deref for Name" },
    { file: "a.rs", lang: "rust", kind: "type", start: 3, end: 3, text: text(3, 3), name: "type Target" },
    { file: "a.rs", lang: "rust", kind: "fn", start: 4, end: 6, text: text(4, 6), name: "fn deref" },
    { file: "a.rs", lang: "rust", kind: "impl", start: 8, end: 12, text: text(8, 12), name: "impl Big" },
    { file: "a.rs", lang: "rust", kind: "fn", start: 9, end: 11, text: text(9, 11), name: "fn a" },
  ];
  // New impl Deref (2-7) + a changed body line in fn a (10) + impl Big's closing brace (12).
  const changed = new Map([["a.rs", new Set([2, 3, 4, 5, 6, 7, 10, 12])]]);
  const units = changedUnits(all, changed, new Map([["a.rs", lines]]), LANGS);
  assert.deepEqual(units.map((u) => u.name), ["impl Deref for Name", "fn a"]);
  assert.equal(units[0].changed.size, 6); // whole impl marked changed
});

test("gateOn unit: an unchanged status mapping still passes the gate", async () => {
  const probes = await loadProbes([[SHIPPED, "shipped"]]);
  const p = probes.get("misattributed-error");
  assert.equal(p.meta.gateOn, "unit");
  const unit = "for o in orgs {\n    if !known(o) { continue; }\n}\nif verified == 0 { return Err(StatusCode::UNAUTHORIZED); }";
  assert.ok(p.meta.gate.rust.test(unit));
  assert.ok(!p.meta.gate.rust.test("    if !known(o) { continue; }")); // the changed line alone wouldn't
});

test("listProbes: 'true' lists everything, shows direct/always/forced", async () => {
  const all = await listProbes([[SHIPPED, "shipped"]], "true");
  assert.equal(all.split("\n").length, 11);
  assert.match(all, /^panic\tshipped\trust \[fn,impl,top\]\tdirect, gated\t/m);
  assert.match(all, /^secret-debug\tshipped\trust \[type\]\talways, gated on unit\t/m);
  assert.match(all, /^reentry-side-effect\t.*gated on unit/m);
  assert.match(all, /^reentrant-caller\tshipped\trust \[fn,impl\]\talways, gated\t/m);
  assert.match(all, /^misattributed-error\t.*gated on unit/m);
  assert.match(all, /^rules\t.*forced only/m);
  assert.equal((await listProbes([[SHIPPED, "shipped"]], "overbroad")).split("\n").length, 1);
});

test("gitDiff: a moved-on `from` diffs from the merge-base, says so", async () => {
  const { inner } = fixture();
  g(inner, "stash", "-q");
  g(inner, "checkout", "-qb", "feat");
  appendFileSync(join(inner, "src/other.rs"), "pub fn feat() -> u8 { 1 }\n");
  g(inner, "commit", "-qam", "feat");
  g(inner, "checkout", "-q", "main");
  appendFileSync(join(inner, "src/other.rs"), "pub fn main_only() -> u8 { 2 }\n");
  g(inner, "commit", "-qam", "main moves");
  g(inner, "checkout", "-q", "feat");
  const { diff, note } = await gitDiff(inner, { from: "main" });
  assert.match(note, /^from main → merge-base [0-9a-f]{10} \(main is not an ancestor of HEAD\)$/);
  assert.ok(diff.includes("+pub fn feat()"));
  assert.ok(!diff.includes("main_only"), "main's own commit is not in the review");
  const plain = await gitDiff(inner, { from: "main...HEAD" });
  assert.equal(plain.note, undefined);
});

test("gitDiff: path selects a nested repo inside an outer repo with no commits", async () => {
  const { outer } = fixture();
  await assert.rejects(gitDiff(outer, { from: "HEAD" }), new RegExp(`git failed in ${outer}`));
  await assert.rejects(gitDiff(outer, { from: "HEAD", target: "nope" }), /no such path/);
  const { root } = await gitDiff(outer, { from: "HEAD", target: "inner" });
  assert.match(root, /inner$/);
});

// Caller-walk fixture. Everything is new on the branch (empty base commit), so
// every unit is changed and reviewable.
//   client.rs   submit_migrate (one-shot)      <- migrate.rs try_auto_migrate <- service.rs run_inner (loop, unguarded)
//   guarded.rs  submit_once    (one-shot)      <- guarded_loop (loop, behind a done-flag)
//   direct.rs   impl Migrator { fn push_migration } (one-shot in an impl) <- poll_loop (loop)
//   other.rs    private fn send_ping, only called once locally; service.rs's loop
//               calls a send_ping too (its own) -- a private fn's callers are
//               searched in its own file only, so that loop must not count
//   pure.rs     hostname / read_install (no side effect, called from a loop)
const CALLER_FILES = {
  "src/client.rs": `pub fn submit_migrate(c: &Client) -> Result<(), Error> {
    c.post("/migrate").send()?;
    Ok(())
}
`,
  "src/migrate.rs": `pub fn try_auto_migrate(c: &Client) -> Option<()> {
    let found = discover()?;
    submit_migrate(c).ok()
}
`,
  "src/service.rs": `pub fn run_inner(c: &Client, sm: &mut Sm) {
    loop {
        match sm.state {
            State::Initialized => { try_auto_migrate(c); send_ping(c); }
            State::Done => return,
        }
    }
}
`,
  "src/guarded.rs": `pub fn submit_once(c: &Client) -> Result<(), Error> {
    c.post("/once").send()?;
    Ok(())
}

pub fn guarded_loop(c: &Client, sm: &mut Sm, done: &mut bool) {
    loop {
        match sm.state {
            State::Initialized if !*done => { *done = true; submit_once(c); }
            _ => return,
        }
    }
}
`,
  "src/direct.rs": `pub struct Migrator;

impl Migrator {
    pub fn push_migration(&self, c: &Client) {
        c.post("/m").send().ok();
    }
}

pub fn poll_loop(m: &Migrator, c: &Client) {
    while running() {
        m.push_migration(c);
    }
}
`,
  "src/other.rs": `fn send_ping(c: &Client) {
    c.post("/ping").send().ok();
}

pub fn ping_once(c: &Client) {
    send_ping(c);
}
`,
  "src/pure.rs": `pub fn hostname() -> String {
    std::env::var("HOSTNAME").unwrap_or_default()
}

pub fn read_install(p: &Path) -> Option<String> {
    std::fs::read_to_string(p).ok()
}

pub fn status_loop(sm: &mut Sm) {
    loop {
        match sm.state {
            State::Initialized => { let h = hostname(); let i = read_install(Path::new("/x")); }
            _ => return,
        }
    }
}
`,
};

async function callerSetup(jevOpts, files = CALLER_FILES) {
  const repo = mkdtempSync(join(tmpdir(), "jrc-"));
  mkdirSync(join(repo, "src"));
  g(repo, "init", "-q");
  writeFileSync(join(repo, "README"), "x\n");
  g(repo, "add", ".");
  g(repo, "commit", "-qm", "base");
  for (const [f, src] of Object.entries(files)) writeFileSync(join(repo, f), src);
  g(repo, "add", ".");
  g(repo, "commit", "-qm", "branch");
  const { root, diff } = await gitDiff(repo, { from: "HEAD~1" });
  const jev = fakeJev(jevOpts);
  const go = (args) =>
    review({ from: "HEAD~1", ...args }, { dir: root, root, diff, ask: jev.ask, cache: new Map(), probeDirs: [[SHIPPED, "shipped"]] });
  return { jev, go };
}

// "repeats" only for the call-site question on an unguarded loop; everything
// else answers its no-finding option.
const callSiteJev = {
  pick: (ins, opts, state) => {
    if (!ins.includes("can control come back to this line")) return opts.find((o) => ["none", "ok", "consistent", "guarded", "exact", "propagated", "accurate"].includes(o)) ?? null;
    return /guarded_loop/.test(state.unit_path) ? "guarded" : "repeats";
  },
  route: () => 0,
};

test("reentrant-caller: walks callers up hops, covers impls, ignores defs/other-file privates, quiet when guarded", async () => {
  const { go, jev } = await callerSetup(callSiteJev);
  const out = await go({ probes: ["reentrant-caller"] });

  // two hops: submit_migrate -> try_auto_migrate -> run_inner (loop)
  assert.match(lineFor(out, "src/client.rs:1-4 pub fn submit_migrate\t") ?? out, /reentrant-caller: called-on-reentry 0\.80 via try_auto_migrate <- run_inner/);
  // one-shot inside an impl: the impl unit fires via the while loop
  assert.match(lineFor(out, "src/direct.rs:3-7 impl Migrator\t") ?? out, /reentrant-caller: called-on-reentry 0\.80 via poll_loop/);
  // same chain behind a done-flag: Jev says guarded -> no finding
  assert.match(lineFor(out, "src/guarded.rs:1-4 pub fn submit_once\t") ?? out, /ok: reentrant-caller/);
  // private send_ping: only its own file is searched, so service.rs's loop doesn't count
  assert.match(lineFor(out, "src/other.rs:1-3 fn send_ping\t") ?? out, /ok: reentrant-caller/);

  const asked = jev.calls.flatMap((c) => Object.values(c.questions).filter((q) => q.instructions.includes("can control come back")).map(() => c.state));
  const paths = asked.map((s) => s.unit_path);
  assert.ok(!asked.some((s) => s.call_chain.some((c) => c.path.startsWith("src/other.rs"))), paths.join("\n"));
  // the call site is marked, and the chain is spelled out for Jev (run_inner is
  // reached twice: 1 hop from try_auto_migrate's own review, 2 hops from submit_migrate's)
  const runs = asked.filter((s) => s.unit_path.startsWith("src/service.rs"));
  assert.ok(runs.length, paths.join("\n"));
  for (const s of runs) assert.match(s.unit, /^\+ \s+State::Initialized => \{ try_auto_migrate\(c\); send_ping\(c\); \}$/m);
  const chains = runs.map((s) => s.call_chain.map((c) => c.path.split(" ")[0]).join(" > "));
  assert.ok(chains.includes("src/migrate.rs:1-4 > src/client.rs:1-4"), chains.join("\n"));
  assert.ok(chains.includes("src/migrate.rs:1-4"), chains.join("\n"));
});

test("forced probes keep their gate; jev_probe-style ungated dry runs don't", async () => {
  const { go, jev } = await callerSetup(callSiteJev);
  const units = ["src/pure.rs:2", "src/pure.rs:6"];
  const out = await go({ probes: ["reentrant-caller"], units });
  assert.match(out.split("\n")[0], /2 forced probe×unit gated out/);
  assert.ok(!jev.calls.length, "no Jev call for side-effect-free fns");
  assert.ok(!out.includes("called-on-reentry"), out);

  const dry = await go({ probes: ["reentrant-caller"], units, ungated: true });
  assert.ok(!/gated out/.test(dry.split("\n")[0]), dry);
  assert.match(dry, /called-on-reentry/); // ran: walks to status_loop
});

test("withAttrs: #[...] lines above an item join its unit; isTest still sees #[test]", () => {
  const lines = [
    "use x;", // 1
    "/// doc", // 2
    "#[derive(", // 3
    "    Debug,", // 4
    "    Clone,", // 5
    ")]", // 6
    '#[serde(rename_all = "camelCase")]', // 7
    "pub struct C {", // 8
    "    password: String,", // 9
    "}", // 10
    "#[test]", // 11
    "fn t() {}", // 12
  ];
  const c = withAttrs({ file: "a.rs", lang: "rust", kind: "type", start: 8, end: 10, text: lines.slice(7, 10).join("\n") }, lines, LANGS);
  assert.equal(c.start, 3);
  assert.equal(c.head, 8);
  assert.match(c.text, /^#\[derive\(\n    Debug,[\s\S]*pub struct C \{/);
  const t = withAttrs({ file: "a.rs", lang: "rust", kind: "fn", start: 12, end: 12, text: lines[11] }, lines, LANGS);
  assert.equal(t.start, 11);
  assert.equal(isTest(t, [], lines, LANGS), true);
  const plain = { file: "a.rs", lang: "rust", kind: "fn", start: 1, end: 1, text: "use x;" };
  assert.equal(withAttrs(plain, lines, LANGS), plain);
});

test("unreviewedFiles + runReview: deleted, renamed, removals-only, lockfiles, binary and sops files are named", async () => {
  const repo = mkdtempSync(join(tmpdir(), "jru-"));
  mkdirSync(join(repo, "src"));
  g(repo, "init", "-q");
  writeFileSync(join(repo, "src/gone.rs"), "pub fn gone() -> u8 { 1 }\n");
  writeFileSync(join(repo, "src/old.rs"), "pub fn moved() -> u8 {\n    2\n}\n");
  writeFileSync(join(repo, "src/trim.rs"), "pub fn a() -> u8 {\n    let x = 1;\n    x\n}\n");
  writeFileSync(join(repo, "Cargo.lock"), "# lock\n");
  writeFileSync(join(repo, "secrets.yaml"), "k: ENC[AES256_GCM,data:aa==]\nsops:\n    age: []\n");
  writeFileSync(join(repo, "logo.png"), Buffer.from([0x89, 0x50, 0x4e, 0x47, 0, 1, 2, 0]));
  g(repo, "add", ".");
  g(repo, "commit", "-qm", "base");
  g(repo, "rm", "-q", "src/gone.rs");
  g(repo, "mv", "src/old.rs", "src/new.rs");
  writeFileSync(join(repo, "src/trim.rs"), "pub fn a() -> u8 {\n    let x = 1;\n}\n");
  appendFileSync(join(repo, "Cargo.lock"), "[[package]]\n");
  appendFileSync(join(repo, "secrets.yaml"), "j: ENC[AES256_GCM,data:bb==]\n");
  writeFileSync(join(repo, "logo.png"), Buffer.from([0x89, 0x50, 0x4e, 0x47, 0, 9, 9, 0]));
  g(repo, "add", "-A");
  const { root, diff } = await gitDiff(repo, { from: "HEAD" });
  assert.deepEqual(unreviewedFiles(diff).sort(), [
    "Cargo.lock",
    "binary logo.png",
    "deleted src/gone.rs",
    "removals only: src/trim.rs",
    "renamed src/old.rs→src/new.rs",
    "sops-encrypted secrets.yaml",
  ]);
  const jev = fakeJev();
  const out = await review({ from: "HEAD" }, { dir: root, root, diff, ask: jev.ask, cache: new Map(), probeDirs: [[SHIPPED, "shipped"]] });
  assert.match(out, /^No added lines to review; not reviewed: .*deleted src\/gone\.rs/);
  assert.equal(await review({ from: "HEAD" }, { dir: root, root, diff: "", ask: jev.ask, cache: new Map(), probeDirs: [] }), "No changes in that diff.");

  // with a reviewable change too, they go in the header
  appendFileSync(join(repo, "src/new.rs"), "pub fn added() -> u8 {\n    3\n}\n");
  const d2 = await gitDiff(repo, { from: "HEAD" });
  const out2 = await review({ from: "HEAD", questions: { q: { ask: "x?" } } }, { dir: root, root, diff: d2.diff, ask: jev.ask, cache: new Map(), probeDirs: [[SHIPPED, "shipped"]] });
  assert.match(out2.split("\n")[0], / · not reviewed: .*sops-encrypted secrets\.yaml/);
  assert.ok(!/renamed/.test(out2.split("\n")[0]), "the rename now has added lines: it's reviewed");
  assert.ok(!out2.includes("secrets.yaml:"), "ciphertext never becomes a unit");
});

test("any language: files no lang claims become `top` hunks; exclude drops them; probes whitelist by extension", async () => {
  const repo = mkdtempSync(join(tmpdir(), "jra-"));
  g(repo, "init", "-q");
  writeFileSync(join(repo, "default.nix"), "{ pkgs }:\n{\n  a = 1;\n}\n");
  writeFileSync(join(repo, "notes.md"), "# notes\n");
  g(repo, "add", ".");
  g(repo, "commit", "-qm", "base");
  writeFileSync(join(repo, "default.nix"), '{ pkgs }:\n{\n  a = 1;\n  b = builtins.fetchurl "http://x";\n\n}\n');
  appendFileSync(join(repo, "notes.md"), "more\n");
  const user = mkdtempSync(join(tmpdir(), "jp-"));
  writeFileSync(join(user, "nixonly.mjs"), `export const meta = { description: "nix", langs: ["nix"], kinds: ["top"], question: { ask: "Impure fetch?", options: { impure: "yes", ok: "no" } } };`);
  const { root, diff } = await gitDiff(repo, { from: "HEAD" });
  const jev = fakeJev();
  const opts = { dir: root, root, diff, ask: jev.ask, cache: new Map(), probeDirs: [[user, "user"]] };
  const out = await review({ from: "HEAD" }, opts);
  const nix = lineFor(out, "default.nix:2-7 (top level)\t");
  assert.ok(nix, out);
  assert.match(nix, /nixonly: impure 0\.80/);
  assert.match(out, /^notes\.md:1-3 \(top level\)\t.*no probes applied$/m); // md: the nix-only probe skips it
  const nixCall = jev.calls.find((c) => c.state.unit_path === "default.nix:2-7");
  assert.equal(nixCall.state.lang, "nix");
  assert.match(nixCall.state.unit, /^\+   b = builtins\.fetchurl/m);
  const ex = await review({ from: "HEAD", exclude: ["**/*.md"] }, { ...opts, cache: new Map() });
  assert.ok(!/^notes\.md/m.test(ex), ex);
  assert.match(ex.split("\n")[0], /not reviewed: notes\.md/);
});

test("langs: a user lang turns a language's hunks into real units; broken langs are reported", async () => {
  const repo = mkdtempSync(join(tmpdir(), "jrl-"));
  g(repo, "init", "-q");
  writeFileSync(join(repo, "a.py"), "import os\n\ndef old():\n    return 1\n");
  g(repo, "add", ".");
  g(repo, "commit", "-qm", "base");
  appendFileSync(join(repo, "a.py"), "\ndef fresh(x):\n    return os.path.join(x, 'y')\n");
  const langs = mkdtempSync(join(tmpdir(), "jl-"));
  writeFileSync(
    join(langs, "python.mjs"),
    `export const meta = { description: "py", display: "Python", exts: [".py"], grammar: "python", kinds: { fn: "{kind: function_definition}" } };`
  );
  writeFileSync(join(langs, "bad.mjs"), `export const meta = { description: "no exts" };`);
  const { root, diff } = await gitDiff(repo, { from: "HEAD" });
  const jev = fakeJev();
  const out = await runReview(
    { from: "HEAD", questions: { q: { ask: "x?" } } },
    { dir: root, root, diff, ask: jev.ask, cache: new Map(), probeDirs: [], harnessDirs: HARNESS_DIRS, langDirs: [...LANG_DIRS, [langs, "user"]] }
  );
  assert.match(out, /^a\.py:6-7 def fresh\t/m);
  assert.equal(jev.calls[0].state.lang, "Python");
  assert.equal(jev.calls[0].state.kind, "fn");
  assert.match(out.split("\n")[0], /langs failing to load: bad/);
  assert.equal(await moduleKind("python", `export const meta = { exts: [".py"] };`), "lang");
});

test("runHarness: a custom harness defines units, scope and state; probes and questions run on them", async () => {
  const dir = mkdtempSync(join(tmpdir(), "jrh-"));
  mkdirSync(join(dir, "src"));
  writeFileSync(join(dir, "src/a.rs"), "// increments i\nfn f(i: u8) -> u8 {\n    i + 1\n}\n/// Why: the API caps at 255.\nfn g() {}\n");
  writeFileSync(join(dir, "src/b.ts"), "// TODO\nconst x = 1;\n");
  const src = `
    export const meta = { description: "comments", args: { path: "dir" } };
    export const scope = (args) => "SCOPE:comments under " + args.path;
    export async function units(args, h) {
      const dir = h.resolve(args.path);
      const files = await h.files(dir, ["src/**"]);
      const cs = await h.astGrep(dir, ".", { rust: { any: [{ kind: "line_comment" }, { kind: "block_comment" }] }, typescript: { kind: "comment" } }, { kind: "comment" });
      return { units: cs.filter((c) => files.includes(c.file)).map((c) => ({ ...c, changed: null })), dir, header: "comments: " + files.length + " files" };
    }
    export function state(u, base) { return { ...base, file_kind: u.lang }; }`;
  assert.equal(await moduleKind("c", src), "harness");
  const harness = await loadHarness("comments", src, "inline");
  const user = mkdtempSync(join(tmpdir(), "jp-"));
  writeFileSync(join(user, "todo.mjs"), `export const meta = { description: "bare todo", kinds: ["comment"], gate: /TODO/, question: { ask: "Bare TODO?", options: { bare: "yes", ok: "no" } } };`);
  const jev = fakeJev({ pick: (ins, opts, st) => (ins.includes("Useful?") && /Why:/.test(st.unit) ? "ok_useful" : null) });
  const out = await runHarness(
    harness,
    { path: dir, route: true, questions: { useful: { ask: "Useful?", options: { useless: "restates code", ok_useful: "explains why" } } } },
    { directory: "/", ask: jev.ask, cache: new Map(), probeDirs: [[user, "user"]], langDirs: LANG_DIRS }
  );
  const lines = out.split("\n");
  assert.match(lines[0], /^comments: 2 files · 3 unit\(s\)/);
  assert.match(lineFor(out, "src/a.rs:1-1 // increments i\t"), /useful: useless 0\.80/);
  assert.match(lineFor(out, "src/a.rs:5-6 /// Why") ?? out, /\t0\.10\tuseful: useless 0\.10$/); // ok_useful picked: ranked last
  assert.match(lineFor(out, "src/b.ts:1-1 // TODO\t"), /todo: bare 0\.80/);
  assert.equal(lines[lines.length - 1].split("\t")[0], "src/a.rs:5-6 /// Why: the API caps at 255.");
  assert.ok(jev.calls.every((c) => Object.values(c.questions).every((q) => q.instructions.endsWith(`SCOPE:comments under ${dir}`))));
  assert.ok(jev.calls.every((c) => !("neighbours" in c.state) && c.state.file_kind));
  assert.equal(jev.calls.find((c) => c.state.unit_path.startsWith("src/a.rs")).state.lang, "Rust");
});

test("globRe and listLibrary", async () => {
  assert.ok(globRe("**/*.md").test("a/b/c.md") && globRe("**/*.md").test("c.md"));
  assert.ok(!globRe("src/*.rs").test("src/a/b.rs") && globRe("src/**").test("src/a/b.rs"));
  const lib = await listLibrary({ probe: [[SHIPPED, "shipped"]], harness: HARNESS_DIRS, lang: LANG_DIRS });
  assert.match(lib, /## harnesses\ncomments\tshipped\targs: path,glob,skip,lines\t[^\n]*\nedited\tshipped\t[^\n]*\nreview\tshipped\targs: from,to,path,units,tests,exclude\t/);
  assert.match(lib, /^rust\tshipped\t\.rs \[fn,impl,type,mod\]\t/m);
  assert.match(lib, /^typescript\tshipped\t\.ts,\.mts,\.cts,\.tsx /m);
  assert.match(lib, /## probes\n[\s\S]*^panic\tshipped/m);
});

// Struct with a derived Debug: secret-debug sees the derive in the unit and
// follows one field type into another file.
const SECRET_FILES = {
  "src/creds.rs": `#[derive(Debug, Clone)]
pub struct LegacyCredentials {
    pub org: String,
    pub api: ApiConfig,
}

#[derive(Clone)]
pub struct NoDebug {
    pub password: String,
}

#[derive(Debug)]
pub struct Plain {
    pub name: String,
    pub count: u32,
}
`,
  "src/api.rs": `pub struct ApiConfig {
    pub url: String,
    pub password: String,
}
`,
};

test("secret-debug: derive is in the unit, nested secret found via rg, non-Debug and secret-free structs skipped", async () => {
  const { go, jev } = await callerSetup({ pick: (ins) => (ins.includes("derives Debug") ? "leaks" : null), route: () => 0 }, SECRET_FILES);
  const out = await go({ probes: ["secret-debug"] });
  assert.match(lineFor(out, "src/creds.rs:1-5 #[derive(Debug, Clone)]") ?? out, /secret-debug: leaks 0\.80/);
  assert.match(out.split("\n")[0], /2 forced probe×unit gated out/); // NoDebug, ApiConfig: no derive(Debug)
  const asked = jev.calls.filter((c) => Object.values(c.questions).some((q) => q.instructions.includes("derives Debug")));
  assert.equal(asked.length, 1); // Plain: Debug but no secret, own or nested -> no Jev call
  assert.match(asked[0].state.unit, /^\+ #\[derive\(Debug, Clone\)\]/);
  assert.match(asked[0].state.nested_types[0], /src\/api\.rs[\s\S]*password: String/);
});

const HOOKS_SHIPPED = [[fileURLToPath(new URL("./hooks", import.meta.url)), "shipped"]];
const hookOpts = (dir, jev, hookDirs = HOOKS_SHIPPED) => ({
  directory: dir, ask: jev.ask, cache: new Map(), hookDirs, harnessDirs: HARNESS_DIRS, probeDirs: [[SHIPPED, "shipped"]], langDirs: LANG_DIRS,
});

test("hook comment-quality: flags bad comments the edit touched, ignores the rest", async () => {
  const dir = mkdtempSync(join(tmpdir(), "jcc-"));
  const bad = "// This robust, elegant solution leverages caching.\nconst cache = new Map();";
  const good = "// Proxy kills idle sockets at 30s.\nconst TIMEOUT = 25_000;";
  writeFileSync(join(dir, "a.ts"), `${good}\n\n${bad}\n`);
  const jev = fakeJev({ route: (ins, st) => (ins.includes("praise the code") && /robust/.test(st.comment) ? 0.95 : 0.05) });
  const opts = hookOpts(dir, jev);
  const check = (args, tool = "edit") => runHooks({ tool, args: { filePath: join(dir, "a.ts"), ...args } }, opts);

  const hit = await check({ oldString: "x", newString: bad });
  assert.match(hit, /^\[jev comment check\] 1 comment/);
  assert.match(hit, /a\.ts:4-5 \/\/ This robust.*←  puffery 0\.95/);
  assert.equal(jev.calls.length, 1); // only the edited comment was asked about
  assert.equal(await check({ oldString: "x", newString: good }), null);
  assert.match(await check({ content: `${good}\n\n${bad}\n` }, "write"), /puffery/); // write: every comment in the file
  const n = jev.calls.length;
  assert.equal(await check({ oldString: "x", newString: "const y = 2;" }), null); // no comment marker: no Jev call
  assert.equal(jev.calls.length, n);
});

test("runHooks: opt-in dir, tools/files match, shared budget, failures dropped", async () => {
  const dir = mkdtempSync(join(tmpdir(), "jh-"));
  writeFileSync(join(dir, "a.rs"), "fn f() {}\n");
  const hooks = mkdtempSync(join(tmpdir(), "jhd-"));
  const jev = fakeJev();
  const opts = hookOpts(dir, jev, [[hooks, "user"]]);
  const edit = (filePath = join(dir, "a.rs"), tool = "edit") => runHooks({ tool, args: { filePath, oldString: "x", newString: "fn f() {}" } }, opts);
  assert.equal(await edit(), null); // empty user dir: nothing runs (shipped ones are templates)
  writeFileSync(join(hooks, "rs.mjs"), `export const meta = { description: "d", tools: ["edit"], files: /\\.rs$/ };
    export default async (e, h) => "rs " + e.rel + " " + JSON.stringify(e.lines) + " " + h.budget.left;`);
  writeFileSync(join(hooks, "boom.mjs"), `export const meta = { description: "d", tools: ["edit"] }; export default async () => { throw new Error("x"); };`);
  writeFileSync(join(hooks, "slow.mjs"), `export const meta = { description: "d", tools: ["write"] }; export default async () => "write only";`);
  writeFileSync(join(hooks, "broken.mjs"), `export const meta = { description: "no tools" };`);
  assert.equal(await edit(), "rs a.rs [[1,1]] 12"); // boom dropped, slow is write-only, broken never loads as a hook
  writeFileSync(join(dir, "b.ts"), "fn f() {}\n");
  assert.equal(await edit(join(dir, "b.ts")), null); // files: /\.rs$/
  assert.equal(await runHooks({ tool: "edit", args: { filePath: "/nope", newString: "x" } }, opts), null); // never throws
  assert.equal(await runHooks({ tool: "bash", args: { command: "ls" } }, opts), null);
  process.env.JEV_HOOKS = "0";
  assert.equal(await edit(), null);
  delete process.env.JEV_HOOKS;
  assert.equal(await moduleKind("k", `export const meta = { tools: ["edit"] }; export default () => null;`), "hook");
  const lib = await listLibrary({ probe: [[SHIPPED, "shipped"]], harness: HARNESS_DIRS, lang: LANG_DIRS, hookTemplates: HOOKS_SHIPPED, hook: [[hooks, "user"]] });
  assert.match(lib, /^comment-quality\tshipped\toff \(jev_probe enable\)\tedit,write\t/m);
  assert.match(lib, /^rs\tuser\ton\tedit \/\\\.rs\$\/\t/m);
  assert.match(lib, /^broken\tuser\ton\t\tLOAD ERROR/m);
});

test("edited harness + rust-design: units from line ranges, gated questions, per-question threshold", async () => {
  const dir = mkdtempSync(join(tmpdir(), "jrd-"));
  mkdirSync(join(dir, "src"));
  writeFileSync(join(dir, "Cargo.toml"), "[package]\nname = \"x\"\n");
  writeFileSync(join(dir, "src/lib.rs"), "pub fn export(r: &R, pretty: bool) -> u8 {\n    1\n}\n\nfn other() -> u8 {\n    2\n}\n");
  const jev = fakeJev({ route: (ins) => (ins.includes("bool parameter") ? 0.9 : 0.85) });
  const harness = (await loadHarnesses(HARNESS_DIRS)).get("edited");
  const opts = { directory: dir, ask: jev.ask, cache: new Map(), probeDirs: [[SHIPPED, "shipped"]], langDirs: LANG_DIRS };
  const out = await runHarness(harness, { path: join(dir, "src/lib.rs"), lines: [[1, 1]], probes: ["rust-design"] }, opts);
  assert.match(out, /^edited: .* lines 1-1 · 1 unit\(s\)/);
  assert.match(lineFor(out, "src/lib.rs:1-3 pub fn export") ?? out, /rust-design: bool_flag_param 0\.90/);
  const asked = Object.keys(jev.calls[0].questions);
  assert.ok(asked.length < 5, `only gated questions asked: ${asked}`); // bool, primitive (u8)
  assert.equal(jev.calls[0].state.crate_kind, "lib");
  // primitive_domain_value fired at 0.85 but its threshold is 0.9: not in the note
  assert.doesNotMatch(out, /primitive_domain_value/);
  const whole = await runHarness(harness, { path: join(dir, "src/lib.rs"), probes: [] }, opts);
  assert.match(whole, /· 2 unit\(s\)/);
});

test("hook rust-design: advisory lines for the edited fn only; ts edits never reach it", async () => {
  const dir = mkdtempSync(join(tmpdir(), "jrh-"));
  mkdirSync(join(dir, "src"));
  writeFileSync(join(dir, "Cargo.toml"), "[package]\nname = \"x\"\n");
  const src = "pub fn export(r: &R, pretty: bool) -> u8 {\n    1\n}\n\nfn other(pretty: bool) -> u8 {\n    2\n}\n";
  writeFileSync(join(dir, "src/lib.rs"), src);
  writeFileSync(join(dir, "a.ts"), "const x = 1;\n");
  const jev = fakeJev({ route: (ins) => (ins.includes("bool parameter") ? 0.9 : 0.05), pick: () => "none" });
  const hooks = mkdtempSync(join(tmpdir(), "jrhd-"));
  writeFileSync(join(hooks, "rust-design.mjs"), readFileSync(fileURLToPath(new URL("./hooks/rust-design.mjs", import.meta.url)), "utf8"));
  const opts = hookOpts(dir, jev, [[hooks, "user"]]);
  const out = await runHooks({ tool: "edit", args: { filePath: join(dir, "src/lib.rs"), newString: "pub fn export(r: &R, pretty: bool) -> u8 {" } }, opts);
  assert.match(out, /^\[jev rust feedback\] \(advisory/);
  assert.match(out, /src\/lib\.rs:1-3 pub fn export  ←  bool_flag_param 0\.90/);
  assert.doesNotMatch(out, /other/); // not edited
  assert.equal(await runHooks({ tool: "edit", args: { filePath: join(dir, "a.ts"), newString: "const x = 1;" } }, opts), null);
});

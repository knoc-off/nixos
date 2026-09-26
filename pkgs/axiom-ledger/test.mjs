// node:test coverage for the pure/foldable logic in opencode-plugin.js:
// scope derivation, anchor-based staleness, ledger folding, path
// extraction from tool results, and hint selection/formatting. No
// framework, no fixtures -- node:test and assert are stdlib, and
// folding/staleness/hinting are exercised against real temp files since
// it's filesystem-correctness that matters, not a mock.
import test from "node:test";
import assert from "node:assert/strict";
import { mkdtemp, mkdir, rm, utimes, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { __test, HINT_CAP } from "./opencode-plugin.js";
import * as pluginModule from "./opencode-plugin.js";

const {
  readAll,
  ledgerPath,
  parseSource,
  deriveScope,
  captureSrc,
  checkFresh,
  normalizeBlock,
  createLedgerCache,
  extractPaths,
  computeHints,
  tryHint,
  createSessionHinter,
} = __test;

function iso(daysAgoCount) {
  return new Date(Date.now() - daysAgoCount * 86400000).toISOString();
}

async function tmp() {
  return mkdtemp(join(tmpdir(), "axiom-test-"));
}

// ---- ledgerPath ----

test("ledgerPath is stable per start dir and varies with it", () => {
  const a = ledgerPath("/home/u/work/foo");
  const b = ledgerPath("/home/u/work/foo");
  const c = ledgerPath("/home/u/work/bar");
  assert.equal(a, b);
  assert.notEqual(a, c);
  assert.match(a, /^\/.*\/axioms\/foo-[a-f0-9]{6}\.jsonl$/);
});

// ---- parseSource ----

test("parseSource parses path:line and path:start-end", () => {
  assert.deepEqual(parseSource("src/db.rs:88"), { rawPath: "src/db.rs", startLine: 88, endLine: 88 });
  assert.deepEqual(parseSource("src/db.rs:88-120"), { rawPath: "src/db.rs", startLine: 88, endLine: 120 });
  assert.deepEqual(parseSource("src/db.rs"), { rawPath: "src/db.rs", startLine: null, endLine: null });
});

test("parseSource rejects commands and URLs", () => {
  assert.equal(parseSource("git log --oneline -10"), null);
  assert.equal(parseSource("https://example.com/docs"), null);
  assert.equal(parseSource(""), null);
});

// ---- deriveScope ----

test("deriveScope walks up from the cited file to the nearest .git", async () => {
  const root = await tmp();
  await mkdir(join(root, "repo", "src"), { recursive: true });
  await mkdir(join(root, "repo", ".git"));
  await writeFile(join(root, "repo", "src", "db.rs"), "fn main() {}\n");

  const scope = await deriveScope("src/db.rs:1", join(root, "repo"));
  assert.equal(scope, join(root, "repo"));

  await rm(root, { recursive: true, force: true });
});

test("deriveScope falls back to * when source has no resolvable file", async () => {
  const scope = await deriveScope("systemctl status sshd", "/tmp");
  assert.equal(scope, "*");
});

test("deriveScope falls back to * when no .git is found above the file", async () => {
  const root = await tmp();
  await mkdir(join(root, "notrepo"), { recursive: true });
  await writeFile(join(root, "notrepo", "f.txt"), "x\n");
  const scope = await deriveScope("f.txt:1", join(root, "notrepo"));
  assert.equal(scope, "*");
  await rm(root, { recursive: true, force: true });
});

test("deriveScope respects an explicit override", async () => {
  const scope = await deriveScope("src/db.rs:1", "/tmp", "/some/other/repo");
  assert.equal(scope, "/some/other/repo");
});

// ---- normalizeBlock ----

test("normalizeBlock strips common leading indentation and trailing whitespace", () => {
  const out = normalizeBlock(["    foo();  ", "    bar();"]);
  assert.equal(out, "foo();\nbar();");
});

test("normalizeBlock survives a uniform reindent", () => {
  const a = normalizeBlock(["  foo();", "  bar();"]);
  const b = normalizeBlock(["      foo();", "      bar();"]);
  assert.equal(a, b);
});

// ---- captureSrc / checkFresh ----

async function makeRepoFile(content) {
  const root = await tmp();
  const file = join(root, "f.rs");
  await writeFile(file, content);
  return { root, file };
}

test("captureSrc captures size/mtime/anchor for a line-range citation", async () => {
  const { root } = await makeRepoFile("a\nb\nasync fn connect() {\n  ok()\n}\nc\n");
  const src = await captureSrc("f.rs:3-5", root);
  assert.equal(src.line, 3);
  assert.match(src.anchor, /async fn connect/);
  assert.equal(typeof src.size, "number");
  await rm(root, { recursive: true, force: true });
});

test("captureSrc returns null for a non-file source", async () => {
  assert.equal(await captureSrc("nix build --no-link", "/tmp"), null);
  assert.equal(await captureSrc("nonexistent-file.rs:1", "/tmp"), null);
});

test("checkFresh: unchanged file (same size/mtime) is fresh without reading", async () => {
  const { root } = await makeRepoFile("a\nb\nc\n");
  const src = await captureSrc("f.rs:1-3", root);
  const result = await checkFresh({ src });
  assert.equal(result.fresh, true);
  await rm(root, { recursive: true, force: true });
});

test("checkFresh: code inserted above the citation is still fresh, reports drift", async () => {
  const { root, file } = await makeRepoFile("async fn connect() {\n  ok()\n}\n");
  const src = await captureSrc("f.rs:1-3", root);

  await writeFile(file, "// new comment\n// another\nasync fn connect() {\n  ok()\n}\n");
  await utimes(file, new Date(), new Date(Date.now() + 5000));

  const result = await checkFresh({ src });
  assert.equal(result.fresh, true);
  assert.equal(result.drifted, true);
  assert.equal(result.line, 3);

  await rm(root, { recursive: true, force: true });
});

test("checkFresh: an unrelated edit elsewhere in the file stays fresh (no false positive)", async () => {
  const { root, file } = await makeRepoFile("async fn connect() {\n  ok()\n}\nfn unrelated() {}\n");
  const src = await captureSrc("f.rs:1-2", root);

  await writeFile(file, "async fn connect() {\n  ok()\n}\nfn unrelated_totally_rewritten(x: i32) -> i32 { x + 1 }\n");
  await utimes(file, new Date(), new Date(Date.now() + 5000));

  const result = await checkFresh({ src });
  assert.equal(result.fresh, true);
  assert.ok(!result.drifted);

  await rm(root, { recursive: true, force: true });
});

test("checkFresh: the cited code itself changing is flagged", async () => {
  const { root, file } = await makeRepoFile("async fn connect() {\n  ok()\n}\n");
  const src = await captureSrc("f.rs:1-3", root);

  await writeFile(file, "async fn connect() {\n  fail()\n}\n");
  await utimes(file, new Date(), new Date(Date.now() + 5000));

  const result = await checkFresh({ src });
  assert.equal(result.fresh, false);
  assert.equal(result.reason, "changed");

  await rm(root, { recursive: true, force: true });
});

test("checkFresh: a pure reindent of the cited code stays fresh (dedent absorbs it)", async () => {
  const { root, file } = await makeRepoFile("if true {\nasync fn connect() {\n  ok()\n}\n}\n");
  const src = await captureSrc("f.rs:2-4", root);

  await writeFile(file, "if true {\n  async fn connect() {\n    ok()\n  }\n}\n");
  await utimes(file, new Date(), new Date(Date.now() + 5000));

  const result = await checkFresh({ src });
  assert.equal(result.fresh, true);

  await rm(root, { recursive: true, force: true });
});

test("checkFresh: a deleted file is flagged gone", async () => {
  const { root, file } = await makeRepoFile("a\nb\n");
  const src = await captureSrc("f.rs:1-2", root);
  await rm(file);
  const result = await checkFresh({ src });
  assert.equal(result.fresh, false);
  assert.equal(result.reason, "gone");
  await rm(root, { recursive: true, force: true });
});

test("checkFresh: a record with no src block is not checked", async () => {
  assert.equal(await checkFresh({}), null);
});

// ---- readAll (fold) ----

test("readAll folds a post + amend into current state, preserving original fields including scope", async () => {
  const dir = await tmp();
  const path = join(dir, "ledger.jsonl");
  const lines = [
    { id: "k3f9", t: iso(3), agent: "explore-quick", status: "unverified", claim: "c", source: "s", why: "w", scope: "/repo" },
    { amends: "k3f9", t: iso(1), agent: "build", status: "verified", note: "confirmed" },
  ];
  await writeFile(path, lines.map((l) => JSON.stringify(l)).join("\n") + "\n");

  const records = await readAll(path);
  assert.equal(records.length, 1);
  assert.equal(records[0].status, "verified");
  assert.equal(records[0].note, "confirmed");
  assert.equal(records[0].claim, "c"); // original fields survive the amend
  assert.equal(records[0].scope, "/repo");
  assert.equal(records[0].agent, "explore-quick"); // attribution isn't rewritten by the amender

  await rm(dir, { recursive: true, force: true });
});

test("readAll ignores a corrupt line instead of losing the whole ledger", async () => {
  const dir = await tmp();
  const path = join(dir, "ledger.jsonl");
  const good = { id: "ok1", t: iso(1), agent: "build", status: "verified", claim: "c", source: "s", why: "w", scope: "*" };
  await writeFile(path, `${JSON.stringify(good)}\nnot json at all\n`);

  const records = await readAll(path);
  assert.equal(records.length, 1);
  assert.equal(records[0].id, "ok1");

  await rm(dir, { recursive: true, force: true });
});

test("readAll on a missing file returns an empty ledger, not an error", async () => {
  const records = await readAll("/nonexistent/does/not/exist.jsonl");
  assert.deepEqual(records, []);
});

// ---- createLedgerCache ----

test("createLedgerCache re-parses only after the file actually changes", async () => {
  const dir = await tmp();
  const path = join(dir, "ledger.jsonl");
  const rec = { id: "a1", t: iso(1), agent: "build", status: "verified", claim: "c", source: "s", why: "w", scope: "*" };
  await writeFile(path, JSON.stringify(rec) + "\n");

  const read = createLedgerCache(path);
  const r1 = await read();
  const r2 = await read();
  assert.equal(r1, r2); // same array reference: cache hit, no re-parse

  await new Promise((r) => setTimeout(r, 5));
  await writeFile(path, JSON.stringify(rec) + "\n" + JSON.stringify({ ...rec, id: "a2" }) + "\n");
  const r3 = await read();
  assert.notEqual(r3, r1);
  assert.equal(r3.length, 2);

  await rm(dir, { recursive: true, force: true });
});

test("createLedgerCache on a missing file returns empty and doesn't throw on subsequent calls", async () => {
  const read = createLedgerCache("/nonexistent/ledger.jsonl");
  assert.deepEqual(await read(), []);
  assert.deepEqual(await read(), []);
});

// ---- extractPaths ----

test("extractPaths pulls the resolved path from a read result", () => {
  const output = { metadata: { display: { path: "/repo/src/db.rs" } } };
  assert.deepEqual(extractPaths("read", output), ["/repo/src/db.rs"]);
});

test("extractPaths returns nothing for a read with no display path (e.g. an error)", () => {
  assert.deepEqual(extractPaths("read", { metadata: {} }), []);
});

test("extractPaths parses grep's file-header lines, ignoring match-text lines", () => {
  const output = {
    output: [
      "Found 3 matches",
      "/repo/src/db.rs:",
      "  Line 12: async fn connect() {",
      "  Line 88: connect().await",
      "",
      "/repo/src/other.rs:",
      "  Line 1: fn main() {}",
    ].join("\n"),
  };
  assert.deepEqual(extractPaths("grep", output), ["/repo/src/db.rs", "/repo/src/other.rs"]);
});

test("extractPaths on grep with no matches returns nothing", () => {
  assert.deepEqual(extractPaths("grep", { output: "No files found" }), []);
});

test("extractPaths parses glob's bare absolute path lines, ignoring the truncation note", () => {
  const output = {
    output: ["/repo/a.rs", "/repo/b.rs", "", "(Results are truncated. Consider using a more specific path.)"].join("\n"),
  };
  assert.deepEqual(extractPaths("glob", output), ["/repo/a.rs", "/repo/b.rs"]);
});

test("extractPaths on glob with no matches returns nothing", () => {
  assert.deepEqual(extractPaths("glob", { output: "No files found" }), []);
});

test("extractPaths returns nothing for a tool it doesn't cover", () => {
  assert.deepEqual(extractPaths("bash", { output: "/repo/a.rs" }), []);
});

// ---- computeHints ----

function axiomFor(path, overrides = {}) {
  return {
    id: overrides.id || "a1",
    status: "verified",
    agent: "build",
    claim: "some fact",
    t: iso(1),
    scope: "/repo",
    src: { path, size: 1, mtime: 1, line: 1, anchor: "x" },
    ...overrides,
  };
}

test("computeHints returns null when no axiom cites a touched path", async () => {
  const records = [axiomFor("/repo/other.rs")];
  const result = await computeHints(records, ["/repo/db.rs"], new Set());
  assert.equal(result, null);
});

test("computeHints surfaces an axiom whose src path matches a touched path", async () => {
  // axiomFor's src.path doesn't exist on disk, so checkFresh reports
  // !gone here -- that's expected staleness behavior, not what's under
  // test; the staleness formatting itself is covered separately below.
  const records = [axiomFor("/repo/db.rs")];
  const result = await computeHints(records, ["/repo/db.rs"], new Set());
  assert.match(result.text, /axiom a1 \(verified, \d+d(, !\w+)?\): some fact -- axiom_get a1/);
  assert.deepEqual(result.shownIds, ["a1"]);
});

test("computeHints excludes retired axioms", async () => {
  const records = [axiomFor("/repo/db.rs", { status: "retired" })];
  const result = await computeHints(records, ["/repo/db.rs"], new Set());
  assert.equal(result, null);
});

test("computeHints excludes axioms with no src (command/URL citations)", async () => {
  const records = [{ id: "a1", status: "verified", agent: "build", claim: "c", t: iso(1), scope: "*" }];
  const result = await computeHints(records, ["/repo/db.rs"], new Set());
  assert.equal(result, null);
});

test("computeHints excludes ids already hinted this session", async () => {
  const records = [axiomFor("/repo/db.rs")];
  const result = await computeHints(records, ["/repo/db.rs"], new Set(["a1"]));
  assert.equal(result, null);
});

test("computeHints ranks verified > refuted > unverified and caps with an overflow note", async () => {
  const records = [
    axiomFor("/repo/db.rs", { id: "u1", status: "unverified" }),
    axiomFor("/repo/db.rs", { id: "v1", status: "verified" }),
    axiomFor("/repo/db.rs", { id: "r1", status: "refuted" }),
    axiomFor("/repo/db.rs", { id: "u2", status: "unverified" }),
  ];
  const result = await computeHints(records, ["/repo/db.rs"], new Set());
  assert.deepEqual(result.shownIds, ["v1", "r1", "u1"]); // HINT_CAP=3, u2 overflows
  assert.match(result.text, /\.\.\. 1 more, axiom_get/);
  assert.equal(HINT_CAP, 3);
});

test("computeHints flags a stale axiom inline", async () => {
  const root = await tmp();
  const file = join(root, "f.rs");
  await writeFile(file, "a\nb\nc\n");
  const src = await captureSrc("f.rs:1", root);
  await writeFile(file, "totally different\n");
  await utimes(file, new Date(), new Date(Date.now() + 5000));

  const records = [{ id: "s1", status: "verified", agent: "build", claim: "stale one", t: iso(1), scope: root, src }];
  const result = await computeHints(records, [src.path], new Set());
  assert.match(result.text, /!changed/);

  await rm(root, { recursive: true, force: true });
});

// ---- tryHint ----

test("tryHint appends a hint to output.output and marks the id hinted", async () => {
  const records = [axiomFor("/repo/db.rs")];
  const readCached = async () => records;
  const output = { output: "file contents here", metadata: { display: { path: "/repo/db.rs" } } };
  const hinted = new Set();

  await tryHint("read", output, readCached, hinted);

  assert.match(output.output, /file contents here/);
  assert.match(output.output, /axiom a1/);
  assert.ok(hinted.has("a1"));
});

test("tryHint leaves output.output untouched when nothing matches", async () => {
  const readCached = async () => [];
  const output = { output: "file contents here", metadata: { display: { path: "/repo/db.rs" } } };
  await tryHint("read", output, readCached, new Set());
  assert.equal(output.output, "file contents here");
});

test("tryHint swallows a thrown readCachedFn and leaves output.output intact", async () => {
  const readCached = async () => {
    throw new Error("boom");
  };
  const output = { output: "file contents here", metadata: { display: { path: "/repo/db.rs" } } };
  await tryHint("read", output, readCached, new Set());
  assert.equal(output.output, "file contents here");
});

test("tryHint does not re-hint the same id on a second read within the same session", async () => {
  const records = [axiomFor("/repo/db.rs")];
  const readCached = async () => records;
  const hinted = new Set();

  const output1 = { output: "v1", metadata: { display: { path: "/repo/db.rs" } } };
  await tryHint("read", output1, readCached, hinted);
  assert.match(output1.output, /axiom a1/);

  const output2 = { output: "v2", metadata: { display: { path: "/repo/db.rs" } } };
  await tryHint("read", output2, readCached, hinted);
  assert.equal(output2.output, "v2");
});

// ---- createSessionHinter ----
//
// Regression coverage for the bug where dedup state lived in a single Set
// closed over by the plugin factory. The factory is cached per directory
// (opencode's InstanceState.get), and a Task-tool sub-agent's child
// session inherits the parent's InstanceRef instead of getting a fresh
// one -- so one Set was shared by the main session and every sub-agent in
// this directory. That meant only the FIRST session to read a cited file
// ever saw the hint; every later sub-agent, including ones with no shared
// context with that first session, saw nothing. createSessionHinter keys
// dedup on sessionID so each session gets its own Set.

test("createSessionHinter gives different sessions independent dedup state", () => {
  const hintedFor = createSessionHinter();
  const a = hintedFor("session-A");
  const b = hintedFor("session-B");
  a.add("x1");
  assert.ok(a.has("x1"));
  assert.ok(!b.has("x1")); // must not leak across sessions
});

test("createSessionHinter returns the same Set for repeated calls with the same sessionID", () => {
  const hintedFor = createSessionHinter();
  const s1 = hintedFor("session-A");
  s1.add("x1");
  const s2 = hintedFor("session-A");
  assert.equal(s1, s2);
  assert.ok(s2.has("x1"));
});

test("regression: two different sessions reading the same cited file BOTH get the hint", async () => {
  // This is the exact scenario the old shared-Set bug broke: a main
  // session and a Task-tool sub-agent (different sessionID, same
  // directory/plugin instance) both read a file with an axiom on it.
  // Before the fix, only the first session's read would carry the hint.
  const records = [axiomFor("/repo/db.rs")];
  const readCached = async () => records;
  const hintedFor = createSessionHinter();

  const mainOutput = { output: "contents", metadata: { display: { path: "/repo/db.rs" } } };
  await tryHint("read", mainOutput, readCached, hintedFor("main-session"));
  assert.match(mainOutput.output, /axiom a1/, "main session should see the hint");

  const subAgentOutput = { output: "contents", metadata: { display: { path: "/repo/db.rs" } } };
  await tryHint("read", subAgentOutput, readCached, hintedFor("sub-agent-session"));
  assert.match(subAgentOutput.output, /axiom a1/, "sub-agent session must ALSO see the hint");
});

test("createSessionHinter still suppresses a repeat read within the SAME session", async () => {
  const records = [axiomFor("/repo/db.rs")];
  const readCached = async () => records;
  const hintedFor = createSessionHinter();

  const first = { output: "v1", metadata: { display: { path: "/repo/db.rs" } } };
  await tryHint("read", first, readCached, hintedFor("main-session"));
  assert.match(first.output, /axiom a1/);

  const second = { output: "v2", metadata: { display: { path: "/repo/db.rs" } } };
  await tryHint("read", second, readCached, hintedFor("main-session"));
  assert.equal(second.output, "v2");
});

// ---- opencode plugin-loader shape ----
//
// Regression coverage for a real production incident: the module loaded
// fine under node:test (plain ESM import), but opencode's own loader
// (packages/opencode/src/plugin/index.ts) rejected it at runtime with
// "Plugin export is not a function", because it applies stricter rules
// than "does this import" -- and nothing here checked those rules. This
// replicates that loader's exact decision logic (readV1Plugin detect ->
// resolvePluginId -> else getLegacyPlugins) against the REAL module
// namespace, so a future stray `export const` or a missing V1 `id`
// fails this test (and the Nix build) instead of failing silently at
// opencode startup with no tools registered and no obvious cause.
function isRecord(v) {
  return typeof v === "object" && v !== null && !Array.isArray(v);
}

function assertOpencodeCanLoad(mod, spec = "file:///home/u/.config/opencode/plugins/axiom-ledger.js") {
  // packages/opencode/src/plugin/shared.ts: readV1Plugin(..., "detect")
  const def = mod.default;
  if (isRecord(def) && ("id" in def || "server" in def || "tui" in def)) {
    if (def.server !== undefined && typeof def.server !== "function") {
      throw new Error(`invalid server export (got ${typeof def.server})`);
    }
    if (def.server === undefined) throw new Error("V1 default must export server()");
    // shared.ts: resolvePluginId -- "file" source (directory-scanned) requires id
    const id = def.id;
    if (id === undefined) throw new Error(`Path plugin ${spec} must export id`);
    if (typeof id !== "string" || !id.trim()) throw new Error("id must be a non-empty string");
    return; // V1 path resolves -- getLegacyPlugins is never reached
  }

  // packages/opencode/src/plugin/index.ts: getLegacyPlugins -- every
  // named export (default included) must be a function, or an object
  // with a function .server.
  const seen = new Set();
  for (const entry of Object.values(mod)) {
    if (seen.has(entry)) continue;
    seen.add(entry);
    const isFn = typeof entry === "function";
    const hasServerFn = isRecord(entry) && typeof entry.server === "function";
    if (!isFn && !hasServerFn) {
      throw new Error(`Plugin export is not a function (found ${typeof entry})`);
    }
  }
}

test("the real module resolves via opencode's V1 loader path (not the legacy fallback)", () => {
  assert.doesNotThrow(() => assertOpencodeCanLoad(pluginModule));
});

test("guard: a bare-function default with a non-function named export would fail to load", () => {
  // Documents exactly the incident this file regressions-tests: this was
  // this module's shape before the V1-object fix.
  const brokenMod = { default: async () => ({}), HINT_CAP: 3, __test: {} };
  assert.throws(() => assertOpencodeCanLoad(brokenMod), /Plugin export is not a function/);
});

test("guard: a V1 object default with no id fails to load as a directory-scanned plugin", () => {
  const brokenMod = { default: { server: async () => ({}) } };
  assert.throws(() => assertOpencodeCanLoad(brokenMod), /must export id/);
});

test("nudgeFor: fires at NUDGE_EVERY investigative calls, not again until another NUDGE_EVERY, resets on post", async () => {
  const { nudgeFor, NUDGE_EVERY } = pluginModule;
  const tool = (t) => ({ type: "tool", tool: t });
  const msgs = (parts) => [{ info: { sessionID: "s1", role: "assistant" }, parts }];
  const state = new Map();
  const reads = (n) => Array.from({ length: n }, () => tool("read"));

  assert.equal(nudgeFor(msgs(reads(NUDGE_EVERY - 1)), state), null);
  assert.equal(nudgeFor(msgs([...reads(NUDGE_EVERY - 1), tool("edit")]), state), null, "edit is not investigative");
  assert.match(nudgeFor(msgs(reads(NUDGE_EVERY)), state), /axiom_post/);
  assert.equal(nudgeFor(msgs(reads(NUDGE_EVERY + 1)), state), null, "no repeat right after");
  assert.match(nudgeFor(msgs(reads(2 * NUDGE_EVERY)), state), /axiom_post/);

  // A post resets the count; the nudge doesn't fire again until NUDGE_EVERY more.
  const posted = [...reads(2 * NUDGE_EVERY), tool("axiom_post")];
  assert.equal(nudgeFor(msgs([...posted, ...reads(NUDGE_EVERY - 1)]), state), null);
  assert.match(nudgeFor(msgs([...posted, ...reads(NUDGE_EVERY)]), state), /axiom_post/);

  // Sessions are independent.
  assert.match(nudgeFor([{ info: { sessionID: "s2" }, parts: reads(NUDGE_EVERY) }], state), /axiom_post/);
});

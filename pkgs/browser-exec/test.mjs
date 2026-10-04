// node:test coverage for the pure functions in match.mjs (glob matching,
// Tampermonkey-header parsing) and the header helpers in opencode-plugin.js
// (save/list metadata round-trip). Run with `node --test test.mjs`, or via
// `nix flake check` (see this package's `passthru.tests.plugin`).
import test from "node:test";
import assert from "node:assert/strict";
import { parseUserscript, globToRegExp, matchesAny } from "./match.mjs";
import { makeHeader, parseHeader, stripHeader, withHeader, wrapForWorld } from "./opencode-plugin.js";
import { validateChoice, actionSpace, decisionRequest, readDecision, rateWindow, toCriteria, actJs } from "./jevkit.mjs";

test("parseUserscript collects @grant, dropping none", () => {
  const src = ["// ==UserScript==", "// @match https://a/*", "// @grant none", "// @grant jev", "// ==/UserScript=="].join("\n");
  assert.deepEqual(parseUserscript(src).grants, ["jev"]);
  assert.deepEqual(parseUserscript("x").grants, []);
});

const goodChoice = { choice: "a", probabilities: { a: 0.7, b: 0.3 }, confidence: 0.6 };

test("validateChoice accepts a well-formed answer", () => {
  assert.equal(validateChoice(goodChoice, ["a", "b"]).choice, "a");
  assert.equal(validateChoice(goodChoice, { a: null, b: "x" }).choice, "a");
});

test("validateChoice rejects anything that could become a wrong action", () => {
  const bad = [
    { ...goodChoice, choice: "c" }, // not offered
    { ...goodChoice, choice: "b" }, // not the argmax
    { ...goodChoice, probabilities: { a: 0.7 } }, // missing option
    { ...goodChoice, probabilities: { a: 0.9, b: 0.9 } }, // doesn't sum to 1
    { ...goodChoice, confidence: NaN },
    undefined,
  ];
  for (const a of bad) assert.throws(() => validateChoice(a, ["a", "b"]));
});

test("toCriteria turns an option list into a null-described map", () => {
  assert.deepEqual(toCriteria(["x", "y"]), { x: null, y: null });
  assert.deepEqual(toCriteria({ x: "d" }), { x: "d" });
});

const page = {
  url: "https://e/",
  title: "t",
  text: "hello",
  actions: [
    { id: "e1", node: 1, kind: "fill", role: "textbox", label: "Search", value: "" },
    { id: "e2", node: 1, kind: "click", role: "textbox", label: "Open Search", value: "" },
    { id: "e3", node: 2, kind: "click", role: "button", label: "Go", value: "" },
    { id: "e4", node: 3, kind: "select", role: "combobox", label: "Size -> L", value: "l", current_value: "M" },
    { id: "scroll_down", kind: "scroll", label: "Scroll down", delta: 560 },
    { id: "wait", kind: "wait", label: "Wait" },
  ],
};

test("actionSpace groups actions per element and splits controls", () => {
  const { elements, targets, controls } = actionSpace(page.actions);
  assert.equal(elements.length, 3);
  assert.deepEqual(elements[0].operations, ["TYPE_TEXT", "CLICK"]);
  assert.deepEqual(Object.keys(targets.CLICK), ["1", "2"]);
  assert.deepEqual(Object.keys(targets.SELECT), ["3:1"]);
  assert.deepEqual(Object.keys(controls), ["SCROLL_DOWN", "WAIT"]);
});

test("decisionRequest offers caller ops, and TYPE_TEXT only when typing is possible", () => {
  const req = decisionRequest(page, "g", [], { extraOps: { DISMISS: "close the banner" }, canType: false });
  assert.ok(!("TYPE_TEXT" in req.operations));
  assert.ok(!("type_text_target" in req.questions));
  assert.equal(req.operations.DISMISS, "close the banner");
  assert.ok("DONE" in req.operations && "BLOCKED" in req.operations);
  assert.ok("click_target" in req.questions);
});

test("readDecision maps operation+target back to the observed action", () => {
  const req = decisionRequest(page, "g", []);
  const ops = Object.keys(req.operations);
  const probs = (keys, pick) => Object.fromEntries(keys.map((k) => [k, k === pick ? 1 : 0]));
  const d = readDecision(
    {
      answers: {
        operation: { choice: "CLICK", probabilities: probs(ops, "CLICK"), confidence: 1 },
        click_target: { choice: "2", probabilities: probs(["1", "2"], "2"), confidence: 1 },
      },
    },
    req
  );
  assert.equal(d.action.id, "e3");
  const w = readDecision({ answers: { operation: { choice: "WAIT", probabilities: probs(ops, "WAIT"), confidence: 1 } } }, req);
  assert.equal(w.action.kind, "wait");
});

test("rateWindow caps calls per sliding minute", () => {
  let t = 0;
  const hit = rateWindow(2, () => t);
  hit();
  hit();
  assert.throws(hit);
  t = 60001;
  hit();
});

test("actJs embeds model-free data only as JSON literals", () => {
  const js = actJs({ kind: "fill", node: 1 }, "g", "a'); alert(1); ('");
  assert.ok(js.includes(JSON.stringify("a'); alert(1); ('")));
  new Function(`return (async () => {${js}})`); // parses
});

test("parseUserscript extracts name/description/match/run-at", () => {
  const src = [
    "// ==UserScript==",
    "// @name         yt-hide-shorts",
    "// @description  Removes Shorts shelf",
    "// @match        https://www.youtube.com/*",
    "// @run-at       document-idle",
    "// ==/UserScript==",
    "console.log(1);",
  ].join("\n");
  const meta = parseUserscript(src);
  assert.equal(meta.name, "yt-hide-shorts");
  assert.equal(meta.description, "Removes Shorts shelf");
  assert.deepEqual(meta.match, ["https://www.youtube.com/*"]);
  assert.equal(meta.runAt, "document-idle");
});

test("parseUserscript collects repeated @match lines", () => {
  const src = [
    "// ==UserScript==",
    "// @match https://a.example/*",
    "// @match https://b.example/*",
    "// ==/UserScript==",
  ].join("\n");
  assert.deepEqual(parseUserscript(src).match, ["https://a.example/*", "https://b.example/*"]);
});

test("parseUserscript defaults run-at to document-idle when absent", () => {
  const src = ["// ==UserScript==", "// @match https://a.example/*", "// ==/UserScript=="].join("\n");
  assert.equal(parseUserscript(src).runAt, "document-idle");
});

test("parseUserscript on a file with no header returns empty defaults", () => {
  const meta = parseUserscript("console.log(1);");
  assert.equal(meta.name, "");
  assert.deepEqual(meta.match, []);
});

test("globToRegExp: * is a wildcard, everything else literal", () => {
  const re = globToRegExp("https://example.com/*");
  assert.ok(re.test("https://example.com/foo/bar"));
  assert.ok(!re.test("https://evil.com/example.com/"));
});

test("globToRegExp escapes regex metacharacters outside of *", () => {
  const re = globToRegExp("https://example.com/a.b?c=*");
  assert.ok(re.test("https://example.com/a.b?c=1"));
  assert.ok(!re.test("https://exampleXcom/a.b?c=1"));
});

test("matchesAny is true if any pattern matches", () => {
  assert.ok(matchesAny(["https://a.example/*", "https://b.example/*"], "https://b.example/page"));
  assert.ok(!matchesAny(["https://a.example/*"], "https://c.example/page"));
});

test("browser-exec header round-trips description and world", () => {
  const src = withHeader("return 1+1;", "does a thing", "page");
  const parsed = parseHeader(src);
  assert.equal(parsed.description, "does a thing");
  assert.equal(parsed.world, "page");
});

test("browser-exec header defaults world to chrome when absent", () => {
  const parsed = parseHeader("return 1;");
  assert.equal(parsed.world, "chrome");
});

test("browser-exec header rejects an invalid world value, keeping the default", () => {
  const src = [
    "// /// browser-exec",
    '// description = "x"',
    '// world = "nonsense"',
    "// ///",
    "return 1;",
  ].join("\n");
  assert.equal(parseHeader(src).world, "chrome");
});

test("stripHeader removes exactly the header block", () => {
  const body = "return 1;\nreturn 2;\n";
  const withHdr = makeHeader("d", "chrome") + "\n" + body;
  assert.equal(stripHeader(withHdr), body);
});

test("withHeader replaces an existing header rather than stacking", () => {
  const once = withHeader("return 1;\n", "first", "chrome");
  const twice = withHeader(once, "second", "page");
  assert.equal((twice.match(/\/\/\/ browser-exec/g) || []).length, 1);
  assert.equal(parseHeader(twice).world, "page");
  assert.equal(parseHeader(twice).description, "second");
});

test("wrapForWorld leaves a chrome-world body untouched", () => {
  assert.equal(wrapForWorld("return 1;", "chrome", 15000), "return 1;");
});

// Regression: the bridge's own content probe defaults to 8s, so a page-world
// snippet used to be capped there no matter what `timeout` the caller asked
// for -- it has to receive an explicit budget derived from that timeout.
test("wrapForWorld budgets the page-world probe under the caller's timeout", () => {
  const wrapped = wrapForWorld("return 1;", "page", 60000);
  const budget = Number(wrapped.match(/,\s*null,\s*(\d+)\)/)[1]);
  assert.ok(budget > 8000, "budget must exceed the bridge's 8s default");
  assert.ok(budget < 60000, "budget must stay under the socket timeout");
});

test("wrapForWorld escapes backticks and ${} so a body can't break out", () => {
  const wrapped = wrapForWorld("return `a${b}` + '\\\\';", "page", 15000);
  // Everything between the pageEval backticks must be inert: no unescaped
  // backtick or interpolation can survive into the template literal.
  const inner = wrapped.slice(wrapped.indexOf("`") + 1, wrapped.lastIndexOf("`"));
  assert.ok(!/(^|[^\\])`/.test(inner), "no unescaped backtick");
  assert.ok(!/(^|[^\\])\$\{/.test(inner), "no unescaped interpolation");
});

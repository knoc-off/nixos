// node:test coverage for the pure header functions in opencode-plugin.js.
// Run directly with `node --test test.mjs`, or via `nix flake check`
// (see flake.nix's `checks.script-exec`). No framework, no fixtures --
// node:test and assert are stdlib.
import test from "node:test";
import assert from "node:assert/strict";
import {
  makeHeader,
  parseHeader,
  stripHeader,
  withHeader,
} from "./opencode-plugin.js";

test("parseHeader round-trips description, packages, nixPackages", () => {
  const src = withHeader("print(1)\n", "does a thing", ["requests"], ["ffmpeg"]);
  const parsed = parseHeader(src);
  assert.equal(parsed.description, "does a thing");
  assert.deepEqual(parsed.packages, ["requests"]);
  assert.deepEqual(parsed.nixPackages, ["ffmpeg"]);
});

test("parseHeader on a file with no header returns empty defaults", () => {
  const parsed = parseHeader("print(1)\n");
  assert.equal(parsed.description, "");
  assert.deepEqual(parsed.packages, []);
  assert.deepEqual(parsed.nixPackages, []);
});

test("parseHeader on a legacy header (no description line) defaults to empty string", () => {
  const src = [
    "# /// script-exec",
    '# packages = ["numpy"]',
    "# nixPackages = []",
    "# ///",
    "import numpy",
  ].join("\n");
  const parsed = parseHeader(src);
  assert.equal(parsed.description, "");
  assert.deepEqual(parsed.packages, ["numpy"]);
});

test("parseHeader tolerates trailing whitespace on marker lines", () => {
  const src = [
    "# /// script-exec  ",
    '# description = "x"',
    '# packages = ["numpy"]',
    "# nixPackages = []",
    "# ///   ",
    "import numpy",
  ].join("\n");
  const parsed = parseHeader(src);
  assert.deepEqual(parsed.packages, ["numpy"]);
});

test("parseHeader ignores a malformed metadata line instead of throwing", () => {
  const src = [
    "# /// script-exec",
    "# description = not valid json",
    "# packages = also not json",
    "# nixPackages = []",
    "# ///",
    "print(1)",
  ].join("\n");
  const parsed = parseHeader(src);
  assert.equal(parsed.description, "");
  assert.deepEqual(parsed.packages, []);
});

test("stripHeader removes exactly the header block", () => {
  const body = "print(1)\nprint(2)\n";
  const withHdr = makeHeader("d", [], []) + "\n" + body;
  assert.equal(stripHeader(withHdr), body);
});

test("withHeader keeps a shebang line first", () => {
  const src = withHeader("#!/usr/bin/env python3\nprint(1)\n", "d", [], []);
  const lines = src.split("\n");
  assert.equal(lines[0], "#!/usr/bin/env python3");
  assert.equal(lines[1], "# /// script-exec");
});

test("withHeader replaces an existing header rather than stacking", () => {
  const once = withHeader("print(1)\n", "first", ["a"], []);
  const twice = withHeader(once, "second", ["b"], []);
  assert.equal((twice.match(/# \/\/\/ script-exec/g) || []).length, 1);
  assert.deepEqual(parseHeader(twice).packages, ["b"]);
  assert.equal(parseHeader(twice).description, "second");
});

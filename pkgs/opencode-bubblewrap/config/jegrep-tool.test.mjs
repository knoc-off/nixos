// node:test for the bash-nudge classifier in jegrep-tool.js.
// `node --test jegrep-tool.test.mjs`, or via `nix flake check`.
import test from "node:test";
import assert from "node:assert/strict";
import plugin from "./jegrep-tool.js";
const { nudgeFor } = plugin;

test("flags file/search commands at a segment head", () => {
  assert.match(nudgeFor("cat foo.txt"), /`cat` -> use Read/);
  assert.match(nudgeFor("cd src && rg needle"), /`rg` -> use Grep/);
  assert.match(nudgeFor("FOO=1 find . -name x"), /`find` -> use Glob/);
  assert.match(nudgeFor("sed -i s/a/b/ f"), /`sed` -> use Edit/);
  assert.match(nudgeFor("sed -n 1,20p f"), /`sed -n` -> use Read/);
});

test("leaves real shell work and pipes alone", () => {
  assert.equal(nudgeFor("git log | grep foo"), "");
  assert.equal(nudgeFor("nix build .#x"), "");
  assert.equal(nudgeFor("sed s/a/b/"), "");
  assert.equal(nudgeFor(""), "");
});

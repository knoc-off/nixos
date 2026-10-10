// Rust: ast-grep kinds -> unit kinds, plus #[...] handling. tree-sitter puts
// attributes next to an item, not in it, so `attach` pulls them into the unit
// (Jev must see a struct's #[derive(Debug)]) and `isTest` reads #[test] /
// #[cfg(test)] mods.
const anyKind = (ks) => `{any: [${ks.map((k) => `{kind: ${k}}`).join(", ")}]}`;

export const meta = {
  description: "Rust: fn, impl, type (struct/enum/trait/type/union), mod",
  display: "Rust",
  exts: [".rs"],
  grammar: "rust",
  kinds: {
    fn: anyKind(["function_item"]),
    impl: anyKind(["impl_item"]),
    type: anyKind(["struct_item", "enum_item", "trait_item", "type_item", "union_item"]),
    mod: anyKind(["mod_item"]),
  },
  trivial: /^\s*(use\s|mod\s+\w+;|#!?\[|\/\/|[{}();,\]]*\s*$)/,
};

const TEST_ATTR = /^#\[(?:\w+::)*test\b|^#\[cfg\(test\)\]/;

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

// Pull the attribute lines directly above (multi-line `#[derive(\n…\n)]`
// too) into the unit; `head` keeps the item's own first line.
export function attach(u, lines) {
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

// #[test]-style attributes, or inside a #[cfg(test)] mod.
export function isTest(u, all, lines) {
  if (!lines) return false;
  const own = (x) => lines.slice(x.start - 1, (x.head ?? x.start) - 1).map((t) => t.trim());
  const tagged = (x) => [...attrsAbove(lines, x.start), ...own(x)].some((a) => TEST_ATTR.test(a));
  return tagged(u) || all.some((m) => m.kind === "mod" && m.file === u.file && m.start < u.start && u.end <= m.end && tagged(m));
}

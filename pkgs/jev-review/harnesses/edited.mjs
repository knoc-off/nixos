// Code units of one file that an edit touched: the same units, folding and
// test detection as `review`, but from line ranges instead of a git diff, so
// it works on untracked files and sees only this edit. No `lines`: every
// line of the file (an audit of the whole file). `path` may also be a dir
// (every file under it, `glob`-filtered) for audits.
import { stat } from "node:fs/promises";
import path from "node:path";

export const meta = {
  description: "code units (fn/impl/type/…) of a file touched by line ranges, or every unit of a file/dir (audit)",
  args: {
    path: "file (or dir, for an audit)",
    lines: "[[start, end], …] edited ranges; omit = whole file(s)",
    glob: "files under a dir (default **)",
    tests: "include test units",
  },
  neighbours: false,
};

export const scope =
  "Judge the lines of `unit` prefixed '+' (the edited code); unprefixed lines are context. `crate_kind` says whether the file is library code (lib) or a binary (bin).";

// bin: src/main.rs or src/bin/**, unless that crate also has a lib.rs that
// the file is part of (main.rs itself is still bin).
async function crateKind(abs) {
  if (/\/src\/bin\//.test(abs) || /\/src\/main\.rs$/.test(abs)) return "bin";
  for (let d = path.dirname(abs); d !== path.dirname(d); d = path.dirname(d)) {
    const has = async (f) => stat(path.join(d, f)).then(() => true, () => false);
    if (await has("Cargo.toml")) return (await has("src/lib.rs")) ? "lib" : "bin";
  }
  return "lib";
}

export async function units(args, h) {
  if (!args.path) throw new Error("edited needs `path`");
  const target = h.resolve(args.path);
  const isFile = (await stat(target)).isFile();
  const dir = isFile ? path.dirname(target) : target;
  const files = isFile ? [path.basename(target)] : await h.files(dir, args.glob ?? "**");
  const all = (await h.scanUnits(dir, files)).filter((u) => u.lang);
  const fileLines = new Map();
  for (const f of new Set(all.map((u) => u.file))) fileLines.set(f, (await h.read(f, dir)).split("\n"));
  const withAttrs = all.map((u) => h.withAttrs(u, fileLines.get(u.file)));
  const changed = new Map();
  for (const [f, ls] of fileLines) {
    const set = new Set();
    for (const [s, e] of isFile && args.lines ? args.lines : [[1, ls.length]]) for (let l = s; l <= e; l++) set.add(l);
    changed.set(f, set);
  }
  const cu = h.changedUnits(withAttrs, changed, fileLines).filter((u) => args.tests || !u.test);
  if (!cu.length) return { empty: `no code units in ${target}${args.lines ? " for those lines" : ""}` };
  const kinds = new Map();
  for (const u of cu) {
    const abs = path.join(dir, u.file);
    if (!kinds.has(abs)) kinds.set(abs, u.lang === "rust" ? await crateKind(abs) : null);
    u.crate_kind = kinds.get(abs);
  }
  return { units: cu, all: withAttrs, dir, header: `edited: ${target}${args.lines ? ` lines ${args.lines.map(([s, e]) => `${s}-${e}`).join(",")}` : ""}` };
}

export function state(u, base) {
  return u.crate_kind ? { ...base, crate_kind: u.crate_kind } : base;
}

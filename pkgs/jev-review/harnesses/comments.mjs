// Every comment under a file or directory, with the code it annotates.
// Adjacent full-line comments merge into one block; a trailing comment is its
// own unit annotating its line. Jev sees `comment` and `code` separately.
import { stat } from "node:fs/promises";
import path from "node:path";

export const meta = {
  description: "every comment in a file or directory (merged blocks, trailing comments), with the code it annotates",
  args: {
    path: "file or directory to scan",
    glob: "files to include under a directory (default **)",
    skip: "offset into the sorted comment list (200 per call)",
    lines: "only comments overlapping these [start, end] line ranges (a single file's edit)",
  },
  neighbours: false,
};

export const scope =
  "`comment` is the comment under review (comment markers included); `code` is the code it annotates: the declaration or lines below it, the lines its trailing line ends (the comment is on the last line), or for a file header the start of the file. `code` may be an excerpt, so something not shown is not a contradiction. Judge only `comment`.";

const PAGE = 200;
const DOC_GAP = 2; // a declaration starting this many lines below a comment is what it documents
const DECL_LINES = 40;
const BELOW_LINES = 15;
const TRAIL_CONTEXT = 6;
const HEADER_LINES = 60;
// Not prose: shebangs, linter/compiler directives, modelines.
const DIRECTIVE = /^\s*(#!|\/\/\/?\s*<reference|(\/\/|#|\/\*)\s*(eslint|prettier|@ts-|tslint|istanbul|c8|biome|shellcheck|noqa|type:\s*ignore|pylint|fmt:|isort|pragma|vim?:|-\*-|nolint|region|endregion|#region|#endregion)\b)/i;

const RULES = {
  rust: { any: [{ kind: "line_comment" }, { kind: "block_comment" }] },
  typescript: { kind: "comment" },
  tsx: { kind: "comment" },
  javascript: { kind: "comment" },
  python: { kind: "comment" },
  bash: { kind: "comment" },
  nix: { kind: "comment" },
};

export async function units(args, h) {
  if (!args.path) throw new Error("comments needs `path` (a file or directory)");
  const target = h.resolve(args.path);
  const isFile = (await stat(target)).isFile();
  const dir = isFile ? path.dirname(target) : target;
  const files = new Set(await h.files(dir, isFile ? [path.basename(target)] : (args.glob ?? "**")));
  if (!files.size) return { empty: `no files under ${target}` };

  const found = (await h.astGrep(dir, isFile ? [path.basename(target)] : ".", RULES, { kind: "comment" }))
    .filter((c) => files.has(c.file))
    .sort((a, b) => a.file.localeCompare(b.file) || a.start - b.start);

  const lines = new Map();
  const linesOf = async (f) => {
    if (!lines.has(f)) lines.set(f, (await h.read(f, dir)).split("\n"));
    return lines.get(f);
  };

  // Merge adjacent full-line comments; trailing ones stand alone.
  let blocks = [];
  for (const c of found) {
    const ls = await linesOf(c.file);
    const first = c.text.split("\n")[0];
    const trailing = !ls[c.start - 1].trimStart().startsWith(first.trimStart());
    if (!trailing && DIRECTIVE.test(first)) continue;
    const prev = blocks[blocks.length - 1];
    if (!trailing && prev && !prev.trailing && prev.file === c.file && c.start === prev.end + 1) {
      prev.end = c.end;
      prev.comment += "\n" + c.text;
      continue;
    }
    blocks.push({ file: c.file, lang: c.lang, start: c.start, end: c.end, comment: c.text, trailing });
  }
  const commentStarts = new Set(blocks.filter((b) => !b.trailing).map((b) => `${b.file}:${b.start}`));
  if (args.lines) blocks = blocks.filter((b) => args.lines.some(([s, e]) => b.start <= e && b.end >= s));
  if (!blocks.length) return { empty: `no comments in ${files.size} file(s) under ${target}` };

  // Declarations, so a doc comment gets the whole signature/body it documents.
  const decls = await h.scanUnits(dir, isFile ? [path.basename(target)] : undefined).catch(() => []);

  const skip = Number(args.skip ?? 0);
  const page = blocks.slice(skip, skip + PAGE);
  const out = [];
  for (const b of page) {
    const ls = await linesOf(b.file);
    let code, codeStart, codeEnd;
    if (b.trailing) {
      // Its line plus the statement(s) leading up to it, back to a blank line.
      codeEnd = b.start;
      codeStart = b.start;
      while (codeStart > 1 && b.start - codeStart < TRAIL_CONTEXT && ls[codeStart - 2]?.trim()) codeStart--;
      code = ls.slice(codeStart - 1, codeEnd).join("\n");
    } else if (ls.slice(0, b.start - 1).every((l) => !l.trim()) && !ls[b.end]?.trim()) {
      // File header (first in the file, then a blank line): show the file's start.
      codeStart = b.end + 1;
      codeEnd = Math.min(ls.length, codeStart + HEADER_LINES - 1);
      code = ls.slice(codeStart - 1, codeEnd).join("\n");
    } else {
      const between = (d) => Array.from({ length: d.start - b.end - 1 }, (_, i) => b.end + 1 + i).some((l) => commentStarts.has(`${b.file}:${l}`));
      const decl = decls.find((d) => d.file === b.file && d.start > b.end && d.start <= b.end + 1 + DOC_GAP && !between(d));
      codeStart = b.end + 1;
      if (decl) codeEnd = Math.min(decl.end, codeStart + DECL_LINES - 1);
      else {
        codeEnd = codeStart - 1;
        // Stop at a blank line or the next full-line comment (its own unit).
        while (codeEnd < ls.length && codeEnd - codeStart + 1 < BELOW_LINES && ls[codeEnd]?.trim() && !commentStarts.has(`${b.file}:${codeEnd + 1}`)) codeEnd++;
      }
      code = ls.slice(codeStart - 1, codeEnd).join("\n");
    }
    out.push({
      file: b.file,
      lang: b.lang,
      kind: "comment",
      start: b.start,
      end: Math.max(b.end, codeEnd),
      name: b.comment.split("\n")[0].trim().slice(0, 60),
      text: ls.slice(Math.min(b.start, codeStart) - 1, Math.max(b.end, codeEnd)).join("\n"),
      changed: new Set(Array.from({ length: b.end - b.start + 1 }, (_, i) => b.start + i)),
      comment: b.comment,
      code: code || "(nothing: end of block or file)",
      trailing: b.trailing,
    });
  }
  const more = skip + PAGE < blocks.length;
  return {
    units: out,
    dir,
    header: `comments ${skip + 1}-${skip + page.length} of ${blocks.length} in ${files.size} file(s) under ${target}${more ? ` · rerun with skip=${skip + PAGE}` : ""}`,
  };
}

export function state(u, base) {
  return { lang: base.lang, file: u.file, line: u.start, comment: u.comment, code: u.code };
}

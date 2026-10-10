// Changed code in a git diff: the default jev_review pass. Each changed line
// goes to its innermost lang unit (fn/impl/class/…); lines outside any unit,
// and every changed line of a file no lang claims, become `top` units. Test
// units are skipped unless `tests` or picked by `units`.
export const meta = {
  description: "changed code in a git diff (from/to/path), one unit per changed fn/impl/class/…, `top` hunks elsewhere",
  args: {
    from: "base ref (required)",
    to: "target ref; omit for the working tree",
    path: "repo, or a dir/file inside one",
    units: "file:line picks / path prefixes",
    tests: "include test units",
    exclude: "globs of files to leave out",
  },
  neighbours: true,
};

export const scope =
  "Judge only the CHANGED lines of `unit` (prefixed '+'); unprefixed lines are context. " +
  "`neighbours` are the most similar existing units in the repo (with `similarity`, 0..1): context only, never under review.";

export async function units(args, h) {
  if (!args.from) throw new Error("review needs `from` (a base ref)");
  // h.preset: an already-computed diff (tests, or a caller that has one).
  const { root, diff, note } = h.preset ?? (await h.gitDiff(args));
  const dir = h.preset?.dir ?? (args.to ? await h.treeAt(root, args.to) : root);
  const excl = (args.exclude ?? []).map(h.glob);
  const excluded = (f) => excl.some((re) => re.test(f));
  const changed = h.changedLines(diff, (f) => !excluded(f));
  const skipped = h.unreviewedFiles(diff, excluded);
  // sops files: the added lines are ciphertext.
  for (const s of skipped) if (s.startsWith("sops-encrypted ")) changed.delete(s.slice("sops-encrypted ".length));
  const notReviewed = skipped.length ? `not reviewed: ${skipped.slice(0, 20).join(" · ")}${skipped.length > 20 ? ` · +${skipped.length - 20} more` : ""}` : "";
  if (!changed.size && !args.units?.length) return { empty: notReviewed ? `No added lines to review; ${notReviewed}` : "No changes in that diff." };

  let all = await h.scanUnits(dir);
  const fileLines = new Map();
  for (const f of changed.keys()) fileLines.set(f, (await h.read(f, dir)).split("\n"));
  all = all.map((u) => (fileLines.has(u.file) ? h.withAttrs(u, fileLines.get(u.file)) : u));
  const cu = h.changedUnits(all, changed, fileLines);
  const { units: selected, unmatched } = h.selectUnits(all, cu, args.units, !args.tests);
  const testsSkipped = args.units?.length ? 0 : cu.filter((u) => u.test).length * !args.tests;
  return {
    units: selected,
    all,
    dir,
    root,
    header: `repo: ${root}${note ? ` · ${note}` : ""}`,
    counts: testsSkipped ? [`${testsSkipped} test unit(s) skipped`] : [],
    notes: [...(unmatched.length ? [`unmatched units: ${unmatched.join(", ")}`] : []), ...(notReviewed ? [notReviewed] : [])],
  };
}

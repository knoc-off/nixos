// Flags comments an edit added or touched that restate the code, contradict
// it, or read like chat/tutorial output. Only the precise comment-quality
// labels count; maintainer_would_edit, decorative_formatting,
// needs_outside_context and verbosity were noisy on real code.
export const meta = {
  description: "after edit/write: comments in the edit that restate/contradict the code or read like chat output",
};

const LABELS = [
  "contradicts_code", "redundant", "explains_basics", "edit_narration", "chat_leftover", "placeholder",
  "disclaimer", "puffery", "hedging", "tutorial_voice", "commented_out_code", "padded",
  "signature_only_doc", "conversational_register",
];
const MIN = 0.8;
const MAYBE_COMMENT = /\/\/|\/\*|#|"""/;

export async function afterEdit(edit, h) {
  if (!MAYBE_COMMENT.test(edit.added)) return null;
  const r = await h.harness("comments", { path: edit.file, lines: edit.lines }, { probes: ["comment-quality"], only: LABELS });
  const hits = r.reviewed.filter((x) => (x.score ?? 0) >= MIN);
  if (!hits.length) return null;
  const rows = hits.map((x) => {
    const [where, , what] = h.line(x).split("\t");
    return `  ${where}  ←  ${what.replace(/^comment-quality: /, "")}`;
  });
  return (
    `[jev comment check] ${hits.length} comment(s) in this edit look off. Fix or delete each one unless you are sure it is right ` +
    `(it should say what the code can't: why, constraints, units, edge cases):\n${rows.join("\n")}`
  );
}

// Advisory Rust feedback on the units an edit touched: design smells
// (rust-design, per-question thresholds) plus input-reachable panics and
// swallowed errors. Live feedback, not a gate: at most 3 lines.
export const meta = {
  description: "after edit/write of a .rs file: design smells, reachable panics and swallowed errors in the edited units (advisory)",
  tools: ["edit", "write"],
  files: /\.rs$/,
};

const MAX = 3;
const MIN = 0.8; // panic / swallowed-error findings; rust-design applies its own per-question thresholds

export default async function (edit, h) {
  const r = await h.harness("edited", { path: edit.file, lines: edit.lines }, { probes: ["rust-design", "panic", "swallowed-error"] });
  const hits = r.reviewed
    .map((x) => {
      // rust-design already thresholded; the others need MIN.
      const results = Object.fromEntries(Object.entries(x.results).filter(([k, v]) => v.p != null && (k === "rust-design" || v.p >= MIN)));
      return { ...x, results, score: Math.max(0, ...Object.values(results).map((v) => v.p)) };
    })
    .filter((x) => Object.keys(x.results).length)
    .sort((a, b) => b.score - a.score)
    .slice(0, MAX);
  if (!hits.length) return null;
  const rows = hits.map((x) => {
    const [where] = h.line(x).split("\t");
    const what = Object.entries(x.results).map(([k, v]) => `${k === "rust-design" ? "" : `${k}: `}${v.label} ${v.p.toFixed(2)}${v.note ? ` ${v.note}` : ""}`);
    return `  ${edit.rel.slice(0, -x.unit.file.length)}${where}  ←  ${what.join(" · ")}`;
  });
  return `[jev rust feedback] (advisory; act on it only if it fits the task)\n${rows.join("\n")}`;
}

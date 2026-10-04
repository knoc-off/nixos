// Changed unit vs. its nearest same-kind existing units: does it follow the
// repo's way, or copy it? Only asked when a neighbour exists; the similarity
// is in the state so weak matches read as weak.
export const meta = {
  description: "the changed code duplicates, or does the same job differently from, similar existing code in this repo",
  gate: (unit, r) => r.nearest(unit).length > 0,
  routable: "always",
};

export default async function (unit, r) {
  const nbs = r.nearest(unit);
  const a = await r.choose(
    "Compare the changed lines with `neighbours`, the most similar existing code in this repo (see `similarity`; below ~0.4 they are often unrelated).",
    {
      duplicates: "repeats a neighbour closely enough that both should share one helper",
      minor_deviates: "does the same kind of job as a neighbour but differently from how the repo does it (error handling, logging, structure, APIs used)",
      consistent: "follows the same conventions as the neighbours, or the neighbours solve unrelated problems",
    }
  );
  const f = r.finding(a);
  if (f && !f.abstain && nbs[0]) f.note = `≈ ${r.label(nbs[0].unit)} (sim ${nbs[0].sim.toFixed(2)})${f.note ? ` ${f.note}` : ""}`;
  return f;
}

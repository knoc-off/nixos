// Side-effecting fns are fine on their own; the bug is a looping/re-entered
// caller that re-runs them (submit_migrate <- try_auto_migrate <- run_inner,
// called again every time the state machine re-enters Initialized). Jev can't
// see that from the unit, so this is a code probe that always runs when the
// gate passes. Validated against the jev-harness fixture + a real branch:
//  - walks callers up to 3 hops (submit_migrate <- try_auto_migrate <- run_inner)
//  - covers folded impl units (DirectSubmitMigrate::submit_migrate is kind impl)
//  - skips definition lines; private fns only match callers in the same file
//  - asks about the specific '+' call site and its failure/re-entry path,
//    with the call chain spelled out; the generic reentry question on a whole
//    53-line loop answered "guarded"/0.4 for the same code
export const meta = {
  description: "a side-effecting function that is called, directly or via helpers, from looping/re-entered code (state machine, event handler, poll), so the effect may repeat",
  langs: ["rust"],
  kinds: ["fn", "impl"],
  gate: /\b(submit|send|post|put|write|create|insert|delete|migrat|upload|notify|publish|spawn|request)\w*\s*\(/i,
  routable: "always",
};

const LOOPY = /\bloop\b|\bwhile\b|match\s+[^{]*\b(state|status|event|msg|cmd)\b/;
const TEST = /(^|\/)tests?(\/|\.rs$)|_tests?\.rs$/;
const HOPS = 3;
const FANOUT = 12; // ponytail: caller cap per probe run; widen if fan-in matters

// [{name, private}] for the fns this unit defines (all of them for an impl).
// Trait-impl methods have no `pub` but are callable anywhere: not private.
// Units carry their #[...] attributes, so the header is the first non-# line.
const header = (x) => x.text.split("\n").find((l) => !l.trim().startsWith("#")) ?? "";
function defs(u, units) {
  const inTraitImpl = (line) =>
    u.kind === "impl" ? / for /.test(header(u))
      : units.some((x) => x.kind === "impl" && x.file === u.file && x.start <= line && line <= x.end && / for /.test(header(x)));
  return [...u.text.matchAll(/^\s*(pub(?:\([^)]*\))?\s+)?(?:async\s+)?fn\s+(\w+)/gm)]
    .map((m) => ({ name: m[2], private: !m[1] && !inTraitImpl(u.start) }))
    .filter((d) => d.name !== "new" && d.name !== "main");
}

export default async function (unit, r) {
  let frontier = [{ u: unit, defs: unit.kind === "impl" ? defs(unit, r.units) : defs(unit, r.units).slice(0, 1), chain: [] }];
  const seen = new Set([`${unit.file}:${unit.start}`]);
  let worst = null;
  for (let hop = 0; hop < HOPS && frontier.length && seen.size <= FANOUT; hop++) {
    const next = [];
    for (const { u, defs: ds, chain } of frontier) {
      for (const d of ds) {
        let hits = "";
        try {
          hits = await r.run("rg", ["-n", "--no-heading", "--type", "rust", `\\b${d.name}\\s*\\(`, d.private ? u.file : "."], { timeout: 10_000 });
        } catch {
          continue; // rg exits 1 on no match
        }
        for (const line of hits.split("\n")) {
          const m = d.private ? /^(\d+):(.*)$/.exec(line) : /^(?:\.\/)?([^:]+):(\d+):(.*)$/.exec(line);
          if (!m) continue;
          const [file, ln, src] = d.private ? [u.file, Number(m[1]), m[2]] : [m[1], Number(m[2]), m[3]];
          if (TEST.test(file) || new RegExp(`\\bfn\\s+${d.name}\\b`).test(src)) continue;
          const c = r.units
            .filter((x) => x.file === file && x.kind === "fn" && x.start <= ln && ln <= x.end)
            .sort((a, b) => a.end - a.start - (b.end - b.start))[0];
          if (!c || (c.file === u.file && c.start >= u.start && c.end <= u.end)) continue;
          const key = `${c.file}:${c.start}`;
          if (seen.has(key) || seen.size > FANOUT) continue;
          seen.add(key);
          const via = [...chain, { name: d.name, unit: u }];
          if (!LOOPY.test(c.text)) {
            next.push({ u: c, defs: defs(c, r.units).slice(0, 1), chain: via });
            continue;
          }
          const called = via[via.length - 1].name;
          const effect = via[0].name;
          const a = await r.choose(
            `The '+' line calls \`${called}\`, which ${via.length > 1 ? `reaches \`${effect}\`, ` : ""}a side effect (request/write/migration). ` +
              "Follow the loop: after that call fails or returns without advancing, or after any later transition, can control come back to this line for the same input so the side effect runs again?",
            {
              repeats: "yes: some path re-enters and the side effect runs again, with nothing recording it was already attempted",
              guarded: "a flag, state transition or terminal state prevents a second run",
              none: "this line cannot be reached twice",
            },
            r.state(
              {
                unit: r.render({ ...c, changed: new Set([ln]) }),
                unit_path: r.label(c),
                neighbours: [],
                call_chain: [...via].reverse().map((v) => ({ path: r.label(v.unit), code: v.unit.text.split("\n").slice(0, 60).join("\n") })),
              },
              c
            )
          );
          const f = r.finding(a);
          if (f && f.p > (worst?.p ?? 0))
            worst = { p: f.p, label: "called-on-reentry", note: `via ${[...via.map((v) => v.name).slice(1), c.name.replace(/^(pub )?fn /, "")].join(" <- ") || c.name}` };
        }
      }
    }
    frontier = next;
  }
  return worst;
}

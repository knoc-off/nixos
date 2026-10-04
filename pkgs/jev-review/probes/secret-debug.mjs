// Credentials reachable through a derived Debug: `{c:?}` or a tracing field
// prints them. Units carry their #[...] attributes, so the derive is in the
// unit; nested secrets are found by following field types one level with rg
// (LegacyCredentials -> NellyApiConfig.password). From the user's harness
// probe: caught the seeded leak at 1.00 and the real nested one at 0.97.
export const meta = {
  description: "a struct holding a password/secret/token (directly or one field-type deep) that derives Debug, so {:?} or a tracing field prints it",
  langs: ["rust"],
  kinds: ["type"],
  routable: "always",
  gateOn: "unit",
  gate: /#\[derive\([^\]]*\bDebug\b[^\]]*\]\s*(?:#\[[^\n]*\]\s*)*(?:pub(?:\([^)]*\))?\s+)?struct\b/,
};

const SECRET = /\b(password|passwd|secret|token|api_key|private_key|credential)s?\b\s*:/i;
const NESTED = 6; // ponytail: field types followed per struct; one level deep only

// `struct Name` -> { file, text } incl. its attributes, or null. Ends at the
// first line that is only `}`, which is good enough for named-field structs.
async function findStruct(r, name) {
  const hits = await r.run("rg", ["-n", "--no-heading", "--type", "rust", `^\\s*(pub(\\([^)]*\\))?\\s+)?struct\\s+${name}\\b`, "."]).catch(() => "");
  const m = hits.split("\n").find(Boolean)?.match(/^(?:\.\/)?([^:]+):(\d+):/);
  if (!m) return null;
  const lines = (await r.read(m[1])).split("\n");
  let start = Number(m[2]);
  while (start > 1 && /^\s*#\[/.test(lines[start - 2])) start--;
  let end = Number(m[2]);
  while (end < lines.length && !/^\s*}\s*$/.test(lines[end - 1]) && !/;\s*$/.test(lines[end - 1])) end++;
  return { file: m[1], text: lines.slice(start - 1, end).join("\n") };
}

export default async function (unit, r) {
  const nested = [];
  if (!SECRET.test(unit.text)) {
    const types = [...unit.text.matchAll(/:\s*(?:Option<|Vec<|Box<|Arc<)?([A-Z]\w+)/g)].map((m) => m[1]);
    for (const t of [...new Set(types)].slice(0, NESTED)) {
      const s = await findStruct(r, t);
      if (s && SECRET.test(s.text)) nested.push(s);
    }
    if (!nested.length) return null;
  }
  const a = await r.choose(
    "This struct derives Debug. Can a password/secret/token be printed in plain text via {:?}, either from its own fields or from a nested field type shown in `nested_types`?",
    {
      leaks: "yes: a plaintext secret is reachable through the derived Debug",
      safe: "the secret field's type redacts its Debug (e.g. secrecy::SecretString, a manual Debug impl)",
      na: "no secret is actually reachable",
    },
    r.state({ nested_types: nested.map((n) => `${n.file}\n${n.text}`) })
  );
  return r.finding(a);
}

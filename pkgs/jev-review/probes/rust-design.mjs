// Rust design smells in edited code: stringly typed values, bool flags,
// swappable params, invalid states, sentinels, needless clones/shared
// mutability, blocking in async, … Each question has a deterministic gate
// (only asked when the '+' lines could have it) and its own threshold `min`.
// Calibrated 2026-10 on pkgs/*/src (261 units) + a planted fixture: every
// planted smell scores >= 0.75 while real-code false positives sit at
// 0.7-0.85 for stringly_typed (config-file strings), swappable_params
// (lat/lon), primitive_domain_value (u8 percents) and blocking_in_async
// (a one-off remove_file). panics and swallowed errors are the separate
// `panic` / `swallowed-error` probes.
export const meta = {
  description: "Rust design smells in the edited lines (stringly typed, bool flags, swappable params, invalid states, sentinels, needless clone/Rc<RefCell>, blocking in async, missing std traits, …)",
  langs: ["rust"],
  kinds: ["fn", "impl", "type", "top"],
  gate: (unit) => !unit.test,
  routable: "always",
};

const n = (instructions, t, f) => ({ type: "noul", instructions, criteria: { true: t, false: f } });
const TYPE = (u) => u.kind === "type" || u.kind === "impl";

// gate: RegExp over the '+' lines, or (unit, changedText) => bool.
export const QUESTIONS = {
  stringly_typed: {
    min: 0.85,
    gate: /&str|String/,
    q: n(
      "Does `code` use a String or &str for a value that has a small fixed set of valid values, where an enum would fit?",
      "e.g. a `mode: &str` parameter that is matched against 'fast', 'safe', 'debug'.",
      "The string holds open-ended data: names, paths, user messages, text from external input."
    ),
  },
  bool_flag_param: {
    min: 0.7,
    gate: /fn\s+\w+[^)]*:\s*bool/,
    q: n(
      "Does a function in `code` take a bool parameter that switches its behaviour, so that a call like `export(&r, true, false)` does not show what the bools mean?",
      "The bool selects a mode or option of the operation.",
      "No bool parameters, or the function name says what the bool is, as in `set_visible(bool)`."
    ),
  },
  primitive_domain_value: {
    min: 0.95,
    gate: /:\s*&?(u8|u16|u32|u64|u128|usize|i8|i16|i32|i64|i128|isize|f32|f64|String|&str)\b/,
    q: n(
      "Does `code` use a bare integer, float, or string for a value with a unit or domain meaning, such as milliseconds, a user id, meters, or money?",
      "e.g. `timeout: u64`, `user_id: i64`, `price: f64` where a newtype or std type like Duration would prevent mix-ups.",
      "Primitives are used for plain counts, indices, or generic data, or units are already encoded in types."
    ),
  },
  swappable_params: {
    min: 0.95,
    gate: (u, t) => /fn\s+\w+\s*(<[^>]*>)?\s*\(/.test(t) && sameTypedNeighbours(t),
    q: n(
      "Does a function in `code` take two or more adjacent parameters of the same type that a caller could pass in the wrong order without a compile error?",
      "e.g. `fn transfer(from: u64, to: u64, amount: u64)`, `fn resize(width: u32, height: u32)`.",
      "Adjacent parameters have different types, or arguments are passed in a struct."
    ),
  },
  invalid_states: {
    min: 0.8,
    gate: (u, t) => TYPE(u) && /struct\s/.test(t) && /bool|Option</.test(t),
    q: n(
      "Does a type in `code` allow combinations of field values that make no sense together, which an enum would rule out?",
      "e.g. `finished: bool` next to `error: Option<String>` and `data: Option<Vec<u8>>`, where finished=false with data=Some is meaningless.",
      "Every combination of field values is a valid state."
    ),
  },
  sentinel_value: {
    min: 0.8,
    gate: /-1\b|::MAX\b|::MIN\b|return\s+0\b|return\s+""|=>\s*-1|=>\s*0\b|""\.to_string\(\)|String::new\(\)/,
    q: n(
      "Does `code` signal absence or failure with a special value such as -1, 0, an empty string, or u32::MAX instead of Option or Result?",
      "e.g. returning -1 when an item is not found.",
      "Absence and failure are expressed with Option or Result."
    ),
  },
  clone_to_satisfy_borrowck: {
    min: 0.8,
    gate: /\.clone\(\)|\.to_owned\(\)|\.to_vec\(\)|\.to_string\(\)/,
    q: n(
      "Does `code` clone or copy data only to get around a borrow, where borrowing, moving, or restructuring would work without the copy?",
      "e.g. `let items = self.items.clone();` followed by read-only use of `items`.",
      "Both copies are needed afterwards, or the clone is a cheap handle such as an Arc moved into a thread or task."
    ),
  },
  shared_mutability: {
    min: 0.8,
    gate: /RefCell|Mutex|RwLock|Cell</,
    q: n(
      "Does `code` use Rc<RefCell<T>>, Arc<Mutex<T>>, or similar shared mutable state where a single owner or a `&mut` would work?",
      "The value never escapes one owner or one thread, yet is wrapped for shared mutation.",
      "The value really is shared: across threads or tasks, in a graph with cycles, or captured by multiple callbacks."
    ),
  },
  untyped_public_errors: {
    min: 0.8,
    gate: /pub\s+(async\s+)?fn[\s\S]*Result<[^>]*,\s*(String|&'?\w*\s*str|Box<dyn\s+(std::error::)?Error)/,
    q: n(
      "Given `crate_kind`, does a public function or trait in `code` return errors as String, &str, or Box<dyn Error> where callers may need to tell failure kinds apart?",
      "Library code returning `Result<T, String>` or `Box<dyn Error>` from a public API.",
      "Errors use a typed error enum, or this is binary code that only reports errors, e.g. anyhow in main."
    ),
  },
  missing_std_trait: {
    min: 0.75,
    gate: /fn\s+(from_\w+|to_\w+|parse\w*|as_string|to_label|next_\w+|new_default|default_\w+|into_\w+)\s*\(/,
    q: n(
      "Does `code` define a custom method for something a standard trait expresses, such as FromStr, Display, From, TryFrom, Default, or Iterator?",
      "e.g. `fn from_hex_string(s: &str) -> Option<Self>` instead of FromStr, `fn to_label(&self) -> String` instead of Display, a `fn next_item(&mut self)` instead of Iterator.",
      "Standard traits are implemented, or no standard trait matches the operation."
    ),
  },
  blocking_in_async: {
    min: 0.9,
    gate: (u, t) => /\basync\b/.test(u.text) && /std::fs|fs::|thread::sleep|\.read_to_string|File::open|reqwest::blocking|\.lock\(\)|std::process::Command|for\s|while\s/.test(t),
    q: n(
      "Does an async function or block in `code` do blocking work without spawn_blocking?",
      "e.g. std::fs, std::thread::sleep, a blocking HTTP client, or a long CPU-bound loop inside async code.",
      "Async code uses async I/O and timers, or blocking work is moved to spawn_blocking or a thread."
    ),
  },
  leaky_visibility: {
    min: 0.85,
    gate: (u, t) => TYPE(u) && /^\+?\s*pub\s+\w+\s*:/m.test(t),
    q: n(
      "Does `code` make a field or item `pub` that callers could use to break an invariant the type relies on?",
      "e.g. `pub items: Vec<T>` on a type documented as always sorted.",
      "Public fields are plain data with no invariant, like `pub x: f64` on a Point."
    ),
  },
  dyn_for_closed_set: {
    min: 0.85,
    gate: /\bdyn\s+[A-Z]/,
    q: n(
      "Does `code` use Box<dyn Trait> or another trait object for a fixed set of variants all defined inside the crate, where an enum would be simpler?",
      "A private trait with a few known implementors, stored as `Vec<Box<dyn Trait>>`.",
      "The trait is a public extension point, implementors come from other crates, or the set is open-ended."
    ),
  },
  deref_inheritance: {
    min: 0.8,
    gate: /impl\b[^{]*\bDeref(Mut)?\s+for\b/,
    q: n(
      "Does `code` implement Deref or DerefMut on a type to expose another type's methods, as a substitute for inheritance?",
      "e.g. `impl Deref for Admin { type Target = User; ... }`.",
      "No Deref, or the type is a smart pointer or guard around the target."
    ),
  },
  unsafe_unjustified: {
    min: 0.7,
    gate: /\bunsafe\b/,
    q: n(
      "Does `code` contain an unsafe block or unsafe fn whose adjacent comment does not explain why it is sound?",
      "No SAFETY comment, or one that only says it is safe or restates the operation.",
      "Every unsafe has a comment naming the invariant and why it holds here, or there is no unsafe."
    ),
  },
  optional_collection: {
    min: 0.8,
    gate: /Option<\s*(Vec|HashMap|HashSet|BTreeMap|BTreeSet|VecDeque|String)\b/,
    q: n(
      "Does `code` wrap a collection in Option, such as Option<Vec<T>>, where None and an empty collection mean the same thing?",
      "The code treats None as empty, e.g. `tags.unwrap_or_default()` everywhere.",
      "None and empty mean different things, e.g. in a PATCH body None means leave unchanged and an empty list means clear."
    ),
  },
  side_effects_in_adaptor: {
    min: 0.8,
    gate: /\.(map|filter|filter_map|flat_map|take_while|skip_while|inspect)\(\s*(move\s*)?\|[^|]*\|\s*\{/,
    q: n(
      "Does `code` perform side effects such as I/O, logging, or mutation inside an iterator adaptor like map or filter, where a for loop would state the intent?",
      "e.g. `.map(|x| { db.insert(x); x })` or `.filter(|x| { println!(...); ... })`.",
      "Adaptor closures are pure, and side effects sit in for loops or for_each at the end of the chain."
    ),
  },
};

// Two adjacent `name: Type` params with the same type in some fn signature.
function sameTypedNeighbours(t) {
  for (const m of t.matchAll(/fn\s+\w+\s*(?:<[^>]*>)?\s*\(([^)]*)\)/g)) {
    const types = m[1].split(",").map((p) => p.split(":").slice(1).join(":").trim()).filter(Boolean);
    if (types.some((ty, i) => i && ty === types[i - 1])) return true;
  }
  return false;
}

const SCOPE = "`code` in the question means the '+' lines of `unit` (unprefixed lines are context).";

export default async function (unit, r) {
  const t = r.changedText(unit);
  const live = Object.entries(QUESTIONS).filter(([, x]) => (typeof x.gate === "function" ? x.gate(unit, t) : x.gate.test(t)));
  if (!live.length) return null;
  const qs = Object.fromEntries(live.map(([k, x]) => [k, { ...x.q, instructions: `${x.q.instructions}\n${SCOPE}\n${r.scope}` }]));
  const a = await r.ask(qs);
  // args.min overrides every threshold (audits: see everything above it).
  const hits = live
    .map(([k, x]) => [k, a[k]?.noul ?? 0, r.args?.min ?? x.min])
    .filter(([, p, min]) => p >= min)
    .sort((x, y) => y[1] - x[1]);
  if (!hits.length) return null;
  const [[label, p], ...rest] = hits;
  return { p, label, note: rest.length ? `(${rest.map(([k, v]) => `${k} ${v.toFixed(2)}`).join(", ")})` : undefined };
}

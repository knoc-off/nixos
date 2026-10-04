// Style/idiom rules as one choice. Never runs by default: name it in
// `probes`, or pass jev_review `criteria` (which replace these rules).
const DEFAULTS = {
  rust: {
    "needless-clone": "clone/to_string/to_owned/collect where a borrow or a lazy iterator would do",
    "index-loop": "index-based loops instead of iterators",
    "owned-param": "&String/&Vec<T>/&Box<T> parameters instead of &str/&[T]/&T",
    "manual-match": "manual match on Option/Result where combinators, if-let or let-else fit",
    "stringly-typed-error": "errors carried as String/&str instead of a typed error",
    "needless-mut-return": "needless `mut` or explicit `return`",
    "manual-impl": "hand-written impls a derive covers",
  },
  typescript: {
    any: "`any` or needless `as` casts",
    "non-null": "non-null `!` assertions",
    "loose-equality": "`==`/`!=` instead of `===`/`!==`",
    enum: "enums where a string-literal union fits",
    "then-chain": "`.then` chains instead of async/await",
    "let-const": "`let` that is never reassigned",
    "manual-loop": "manual loops where map/filter/find/some fit",
  },
};

export const meta = {
  description: "named style/idiom rules (override with jev_review `criteria`)",
  routable: false,
  question: (unit, r) => {
    const c = r.args?.criteria;
    return {
      ask: `Which rule do the changed ${r.langName} lines violate most clearly? Pick none if they violate no rule.`,
      options: { ...(c?.[unit.lang] ?? c?.all ?? DEFAULTS[unit.lang]), none: "no rule is violated" },
    };
  },
};

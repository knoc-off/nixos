// Prefix / substring / case-insensitive matching where identity was meant:
// is_sibling_name accepting "Nelly_backup" as an install.
export const meta = {
  description: "a name/path/id comparison by prefix, suffix, substring or case-insensitively that also accepts unrelated values (e.g. a 'foo_backup' folder counting as 'foo')",
  gate: {
    rust: /starts_with|ends_with|contains|to_lowercase|to_uppercase|eq_ignore_ascii_case|strip_prefix|strip_suffix|Regex::new|\bglob\b/,
    typescript: /startsWith|endsWith|includes\(|indexOf\(|toLowerCase|toUpperCase|localeCompare|new RegExp|\/[^/\n]+\/[gimsuy]*\.test\(|match\(/,
  },
  question: {
    ask: "Does a string/name/path match in the changed lines accept more than it should? Think of a concrete near-miss value (backup copy, longer name with the same prefix, different case).",
    options: {
      overbroad: "a near-miss value (e.g. 'foo_backup', 'foobar', 'FOO') would be accepted although it is not the intended thing",
      exact: "the match only accepts what it should, or loose matching is clearly intended",
      none: "the changed lines have no such matching",
    },
  },
};

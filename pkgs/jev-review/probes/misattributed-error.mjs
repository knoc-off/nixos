// Errors that blame the wrong cause: every org skipped for an unknown
// integration_type -> 401 "no credentials verified". The change that causes
// it is small (a `continue`), the status mapping it falls through to is
// unchanged -- so the gate looks at the whole unit, and the question is
// about paths the change creates or alters.
export const meta = {
  description:
    "an error, status code or message that blames the wrong cause, e.g. a fallthrough or empty-result path reporting 'unauthorized'/'not found' when the real reason was something else (all items skipped, unsupported type, parse failure)",
  kinds: ["fn", "impl", "class", "top"],
  gateOn: "unit",
  gate: {
    rust: /Err\(|bail!|anyhow!|StatusCode|\bstatus\b|\b[45]\d\d\b|Error::/,
    typescript: /\bthrow\b|reject\(|\bstatus\b|\b[45]\d\d\b|Error\(/,
  },
  question: {
    ask:
      "Follow every path the CHANGED lines create or alter (a new continue/skip/filter, a new early return, a changed condition) to the error, status code or message it ends in -- also when that error is in unchanged code further down. Does any such path end in an error that names a different cause than the one that actually led there? Consider: all items skipped, empty input, unsupported type, fallthrough after filters.",
    options: {
      misattributed: "a path the change creates/alters ends in an error/status that blames a different cause (e.g. 'unauthorized' when every item was skipped as unsupported)",
      minor_vague: "the error is technically right but drops the specific cause that was known at that point",
      accurate: "every error/status reachable from the changed paths names the real cause",
      none: "the changed lines create or alter no path to an error",
    },
  },
};

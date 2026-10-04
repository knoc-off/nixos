// Errors that disappear. Distinguishes silent from logged from propagated,
// which a yes/no question blurred (discover_legacy_installs: all but one
// early return logged a warning).
export const meta = {
  description: "an error or failed result that is discarded, or only logged where the caller needs to know, so a failure looks like success",
  gate: {
    rust: /\.ok\(\)|let _ =|unwrap_or|unwrap_or_default|unwrap_or_else|\.ok\?|if let (Ok|Some)|Err\(_\)|=> \{\s*\}|=> \(\)|filter_map|flatten\(\)|warn!|error!|return (None|Ok\(\(\)\)|;)/,
    typescript: /catch|\.catch\(|\?\.|\?\?|return (null|undefined|\[\]|;)|console\.(warn|error)|void /,
  },
  question: {
    ask: "Look at every place in the changed lines where an error, Err, None, rejected promise or failed call is handled. What happens to the failure?",
    options: {
      silent: "at least one failure is discarded with no log and no propagation, and the caller cannot tell it happened",
      "logged-only": "failures are logged but swallowed where the caller needed to react (it continues as if it succeeded)",
      propagated: "failures are propagated or deliberately handled; any swallowing is justified by the context",
      none: "no failure handling in the changed lines",
    },
  },
};

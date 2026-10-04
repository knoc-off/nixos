// Side effects that repeat because the code they sit in loops or is
// re-entered (state machines, event handlers, polling). Gated on that shape,
// not on "has a side effect": a one-shot HTTP wrapper is the caller's
// business (see reentrant-caller), and asking it here flagged every wrapper.
// The gate tests the whole unit: a change inside a state-machine arm rarely
// touches the `loop`/`match` line, so the changed-lines gate never reached
// run_inner / auth_state.
export const meta = {
  description:
    "a side effect (request, write, migration, message, spawn) inside looping/re-entered code (state machine, event handler, poll, retry loop) that repeats on every pass with nothing recording that it already happened",
  kinds: ["fn", "impl", "class", "top"],
  gateOn: "unit",
  gate: {
    rust: /\bloop\b|\bwhile\b|match\s+[^{]*\b(state|status|event|ev|msg|message|cmd)\b|\bState::|\bStatus::|\bEvent::|\b(on_\w+|handle_\w+|run_inner|tick|poll|retry|reconnect)\b/,
    typescript: /\bwhile\b|setInterval|useEffect|\bon[A-Z]\w*\b|\.on\(|addEventListener|subscribe\(|\b(retry|poll|tick|reconnect)\w*/,
  },
  question: {
    ask:
      "Trace the changed code through a second pass of its loop / a re-entry of the same state or event. Does a side effect (request, write, migration, message, spawn) introduced or touched by the changed lines run again?",
    options: {
      repeats: "yes: on every pass/re-entry it repeats, with no done-flag, state check, idempotency key or once-guard",
      guarded: "the side effect is guarded (flag, state transition, idempotent API) or only happens once by construction",
      none: "the changed lines add or touch no side effect inside the looping/re-entered path",
    },
  },
};

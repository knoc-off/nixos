// Input-dependent panics in non-test Rust. The gate wants a real panicking
// call, so unwrap_or / unwrap_or_default / unwrap_or_else never get here, and
// test units never do either, even with tests: true (an unwrap in a test is
// the test failing, which is fine). The "only breaks if an invariant here
// breaks" answer is ok_invariant: it is not a finding (as `invariant` it
// ranked safe test code at p 0.6).
const RE = /\.(unwrap|expect|unwrap_err|expect_err)\(|\bpanic!|\bunreachable!|\btodo!|\bunimplemented!|\[[^\]\n]*\]\s*(?:[.;)]|$)/m;

export const meta = {
  description: "an unwrap/expect/index/panic in non-test code that can panic on real input (not a provable invariant)",
  langs: ["rust"],
  kinds: ["fn", "impl", "top"],
  gate: (unit, r) => !unit.test && RE.test(r.changedText(unit)),
  question: {
    ask: "Can any .unwrap()/.expect()/slice index/panic!/unreachable! in the changed lines panic on input that can actually occur at runtime? (unwrap_or, unwrap_or_default and unwrap_or_else never panic.)",
    options: {
      panics: "a reachable input (missing file, bad data, empty collection, network failure, user input) makes it panic",
      ok_invariant: "it can only panic if an invariant established right here is broken (and the code shows that invariant)",
      none: "nothing in the changed lines can panic",
    },
  },
};

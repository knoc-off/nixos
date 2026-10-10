// One Jev request per comment carrying 20 questions (19 noul, 1 score);
// p = the worst signal, label = which one, note = the other flags >= 0.5.
export const meta = {
  description: "comment smells: restates/contradicts code, chat/tutorial voice, placeholder, padding, puffery, hedging, … (for the `comments` harness)",
  kinds: ["comment"],
  routable: "always",
};

const n = (instructions, t, f) => ({ type: "noul", instructions, criteria: { true: t, false: f } });

export const QUESTIONS = {
  adds_hidden_info: n(
    "Does `comment` tell the reader something that cannot be read from `code`, such as a reason, constraint, invariant, unit, edge case, external behaviour, or reference?",
    "At least one fact in the comment is not visible in the code, e.g. why a retry exists, which API quirk forces a workaround, what unit a number is in.",
    "Everything the comment says can be read directly from the code."
  ),
  maintainer_would_edit: n(
    "Would an experienced maintainer reviewing `comment` in a code review ask for it to be shortened, reworded, corrected, or deleted?",
    "A reviewer would request a substantive change: cut words, delete it, fix a wrong or vague claim, or replace chat-like or promotional phrasing.",
    "A reviewer would accept it as is. Pure taste, such as capitalization or a missing period, does not count."
  ),
  conversational_register: n(
    "Is `comment` written in a spoken, conversational register rather than terse technical prose?",
    "Uses narration in first or second person, rhetorical questions, or spoken phrasing, e.g. 'we want to make sure', 'you'll notice', 'Okay, so here', 'Why? Because the cache...'.",
    "Terse declarative statements, e.g. 'Retries once: the API drops the first request after idle.'"
  ),
  verbosity: {
    type: "score",
    instructions: "How much of `comment` could be removed without losing any information about `code`?",
    criteria: [
      "Nothing: every word carries information.",
      "A little: a few filler words or one redundant clause.",
      "About half: preamble, restatement, or filler such as 'Note that', 'In order to', 'This function is responsible for'.",
      "Most of it: the point fits in a fraction of the length.",
    ],
  },
  restates_code: n(
    "Does `comment` only repeat what `code` already shows through its names, calls, operators, and literals?",
    "The comment paraphrases the code, e.g. '# increment counter' above `counter += 1`, or '// loop over users' above `for (const user of users)`.",
    "The comment says something the code does not."
  ),
  contradicts_code: n(
    "Does `comment` describe behaviour that `code` does not have?",
    "The comment is wrong or out of date about the code, e.g. says 'returns null on failure' while the code throws.",
    "What the comment claims matches the code."
  ),
  explains_basics: n(
    "Does `comment` explain a basic language feature or standard library call that any programmer in this language already knows?",
    "e.g. '# import the os module', '// return the result', '# loop through the list', '// create a new array'.",
    "The comment is about this program, not about how the language works."
  ),
  edit_narration: n(
    "Does `comment` describe a change made to the code instead of the code as it is now?",
    "It narrates an edit or history, e.g. 'Updated to use the new API', 'Fixed: now handles empty input', 'changed from 30 to 60', 'previously used a dict'.",
    "It describes the code in its current form only."
  ),
  chat_leftover: n(
    "Is `comment` written as a reply to a person in a conversation?",
    "It addresses someone who made a request, e.g. 'Here is the updated function', 'Let me add validation', 'As requested', 'I added error handling', 'your existing code'.",
    "It is a note about the code for whoever maintains it."
  ),
  placeholder: n(
    "Does `comment` stand in for code that is missing or left out?",
    "e.g. '... rest of the implementation', '// existing code unchanged', '# add your logic here', 'omitted for brevity', 'TODO: implement'.",
    "The comment sits next to code that is actually present."
  ),
  disclaimer: n(
    "Does `comment` say the code is simplified, a demo, not production ready, or that a real implementation would do something different?",
    "e.g. 'This is a simplified version', 'In production you would use a proper queue', 'for demonstration purposes', 'you may want to add retries'.",
    "The comment makes no claim about the code being incomplete or illustrative."
  ),
  puffery: n(
    "Does `comment` praise the code with evaluative words instead of stating a concrete property?",
    "Uses words like robust, efficient, clean, elegant, comprehensive, seamless, powerful, production-ready, leverages, ensures, without saying what concretely makes it so.",
    "Any quality claim is concrete and checkable, e.g. 'O(n) because the input is pre-sorted'."
  ),
  hedging: n(
    "Does `comment` express doubt about whether the code is correct or works?",
    "e.g. 'this should work', 'hopefully handles most cases', 'might need adjusting', 'I think this is right'.",
    "The comment states facts without doubting the code. A documented known limitation counts as false."
  ),
  tutorial_voice: n(
    "Is `comment` written as a lesson or step-by-step walkthrough for a learner rather than a note for a maintainer?",
    "e.g. 'Step 1: parse the input', 'First, we create a client', 'Now we loop over the results', 'Here we check if the user exists'.",
    "It reads like a note between colleagues who know the language."
  ),
  commented_out_code: n(
    "Is `comment` disabled source code rather than prose?",
    "The comment body is code, e.g. '// console.log(user)', '# x = compute(y)'.",
    "The comment body is natural language, possibly with short inline code references."
  ),
  padded: n(
    "Could `comment` be cut to half its length or less without losing any information?",
    "It contains filler such as 'Note that', 'It is worth noting', 'In order to', 'This function is responsible for', 'The following code', or repeats itself.",
    "Nearly every word carries information."
  ),
  needs_outside_context: n(
    "Does understanding `comment` require knowing a codename, term, ticket, or earlier discussion that the comment does not explain or link to?",
    "e.g. 'workaround for the Phoenix issue', 'as discussed', 'per the new approach', with no link or definition.",
    "A programmer new to the file can understand the comment on its own. A comment with an issue number or URL counts as false."
  ),
  describes_other_code: n(
    "Does `comment` describe code that is not in `code`, such as the whole function, file, module, or project?",
    "The comment talks about something beyond the lines it annotates.",
    "The comment is about the lines in `code`."
  ),
  decorative_formatting: n(
    "Does `comment` use decorative formatting typical of chat output?",
    "Contains emoji, check marks, arrows, Markdown bold or headings, divider lines such as '=====', em dashes, or emphasis markers such as 'IMPORTANT:' or exclamation marks.",
    "Plain text with ordinary punctuation."
  ),
  signature_only_doc: n(
    "Does `comment` only repeat the declared name, parameter names, and types from `code`, without describing behaviour, side effects, errors, or edge cases?",
    "e.g. 'Gets the user. @param id The id. @returns The user.' above `getUser(id)`.",
    "It says something a caller could not infer from the signature alone."
  ),
};

// Context, not findings: shown in the note, never ranked. describes_other_code
// is normal for file/function headers.
const CONTEXT = new Set(["adds_hidden_info", "describes_other_code", "verbosity"]);

export default async function (unit, r) {
  const qs = Object.fromEntries(Object.entries(QUESTIONS).map(([k, q]) => [k, { ...q, instructions: `${q.instructions}\n${r.scope}` }]));
  const a = await r.ask(qs);
  const v = {};
  for (const [k, x] of Object.entries(a)) if (!CONTEXT.has(k)) v[k] = x?.noul ?? 0;
  // Redundant: restates the code AND adds nothing hidden.
  v.redundant = Math.min(v.restates_code, 1 - (a.adds_hidden_info?.noul ?? 1));
  delete v.restates_code;
  // Score answer: { score: expected level 0..3, probabilities }. Often near-flat,
  // so half weight: it can rank a comment but rarely lead.
  const lvl = Number.isFinite(a.verbosity?.score) ? a.verbosity.score : null;
  if (lvl != null) v.verbose = lvl / 6;
  // args.only: rank by these labels alone (the edit hook keeps the precise ones).
  const ranked = Object.entries(v)
    .filter(([k]) => !r.args?.only || r.args.only.includes(k))
    .sort((x, y) => y[1] - x[1]);
  if (!ranked.length) return null;
  const [[label, p]] = ranked;
  if (p < 0.1) return null;
  const also = ranked.slice(1).filter(([k, x]) => x >= 0.5 && k !== "verbose").map(([k, x]) => `${k} ${x.toFixed(2)}`);
  if (lvl != null) also.push(`verbosity ${lvl.toFixed(1)}/3`);
  return { p, label, note: also.length ? `(${also.join(", ")})` : undefined };
}

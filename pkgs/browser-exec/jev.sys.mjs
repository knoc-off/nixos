// Jev (TypeSafe's System One model) for browser-exec scripts.
//
// Runs in the parent process. The API key never leaves this module: chrome
// snippets get the `jev` object from the bridge sandbox, and userscripts that
// declare `// @grant jev` get a proxy that messages BrowserExecUserscriptParent,
// which calls in here. A page can at worst spend quota through a granted
// userscript, which is capped by the per-minute budget below.
//
// Key, in order: $TYPESAFE_API_KEY, then the file named by pref
// browserexec.jevKeyFile (default /run/secrets/jev/api-key, the sops secret
// modules/jegrep.nix declares). Every call is appended to
// ~/.local/share/browser-exec/jev.log (question ids/types, answers, latency,
// usage -- not the state, which can hold page content).
import {
  noulQ,
  choiceQ,
  scoreQ,
  validateChoice,
  decisionRequest,
  readDecision,
  rateWindow,
  SNAPSHOT_JS,
  actJs,
  VALUE,
} from "./jevkit.mjs";

const { setTimeout, clearTimeout } = ChromeUtils.importESModule("resource://gre/modules/Timer.sys.mjs");
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

const ENDPOINT = "https://api.typesafe.ai/v1/systemone";
const pref = (name, fallback) => {
  try {
    return typeof fallback === "number"
      ? Services.prefs.getIntPref(name)
      : Services.prefs.getStringPref(name);
  } catch (_) {
    return fallback;
  }
};

let cachedKey = null;
async function apiKey() {
  if (cachedKey) return cachedKey;
  const env = Services.env.get("TYPESAFE_API_KEY");
  if (env) {
    cachedKey = env.trim();
    return cachedKey;
  }
  const file = pref("browserexec.jevKeyFile", "/run/secrets/jev/api-key");
  try {
    cachedKey = (await IOUtils.readUTF8(file)).trim();
  } catch (e) {
    throw new Error(`no Jev API key: set TYPESAFE_API_KEY or make ${file} readable (${e})`);
  }
  return cachedKey;
}

const budget = rateWindow(pref("browserexec.jevPerMinute", 120));
const LOG = Services.env.get("HOME") + "/.local/share/browser-exec/jev.log";

function log(entry) {
  IOUtils.writeUTF8(LOG, JSON.stringify({ ts: new Date().toISOString(), ...entry }) + "\n", {
    mode: "append",
  }).catch(() => {});
}

// One request: { state, questions } -> { model, answers, usage }.
// `caller` only labels the log line.
export async function ask(state, questions, { model, caller = "chrome" } = {}) {
  budget();
  const body = JSON.stringify({ model: model || pref("browserexec.jevModel", "jev-latest"), state, questions });
  const started = Date.now();
  for (let attempt = 0; ; attempt++) {
    // AbortSignal.timeout() needs a window ("Could not find window" in a
    // system module), so time out by hand.
    const abort = new AbortController();
    const timer = setTimeout(() => abort.abort(), 25000);
    const res = await fetch(ENDPOINT, {
      method: "POST",
      headers: { Authorization: `Bearer ${await apiKey()}`, "Content-Type": "application/json" },
      body,
      signal: abort.signal,
    }).finally(() => clearTimeout(timer));
    if ([429, 503, 529].includes(res.status) && attempt < 2) {
      await sleep(500 * 2 ** attempt);
      continue;
    }
    if (res.status === 401) cachedKey = null; // rotated secret: re-read next time
    if (!res.ok) {
      const detail = (await res.text()).slice(0, 500);
      log({ caller, error: res.status, detail });
      throw new Error(`Jev HTTP ${res.status}: ${detail}`);
    }
    const out = await res.json();
    log({
      caller,
      ms: Date.now() - started,
      model: out.model,
      usage: out.usage,
      questions: Object.fromEntries(Object.entries(questions).map(([k, q]) => [k, q.type])),
      answers: Object.fromEntries(
        Object.entries(out.answers || {}).map(([k, a]) => [k, a.choice ?? a.score ?? a.noul])
      ),
    });
    return out;
  }
}

// Single-question conveniences. Each returns just that question's answer.
export async function noul(state, instructions, opts) {
  return (await ask(state, { q: noulQ(instructions) }, opts)).answers.q.noul;
}

export async function choose(state, instructions, options, opts) {
  const q = choiceQ(instructions, options);
  return validateChoice((await ask(state, { q }, opts)).answers.q, q.criteria);
}

export async function score(state, instructions, levels, opts) {
  return (await ask(state, { q: scoreQ(instructions, levels) }, opts)).answers.q;
}

// The functions a userscript may reach over the actor. Everything else
// (observe/act/run) needs chrome-side pageEval and is chrome-world only.
export const USERSCRIPT_API = { ask, noul, choose, score };

// Chrome-world API, bound to the bridge's pageEval.
export function makeJev(pageEval) {
  const observe = (target) => pageEval(SNAPSHOT_JS, target);

  async function act(action, page, { text, target } = {}) {
    return pageEval(actJs(action, page.guards?.[action.node], text), target);
  }

  // Agent loop, after browser-use/jev-ultrafast: one speculative request per
  // cycle (operation + a target per operation), execute, re-observe.
  //
  //   goal          what "done" means, in plain language
  //   values        strings TYPE_TEXT may enter; omitted = no typing offered
  //   ops           { NAME: { description, run(page) } } extra operations
  //                 (inline logic, or `() => snippet("name")` for a saved one)
  //   minConfidence stop with status "uncertain" below this operation confidence
  //   target        tab/window target, as for pageEval
  async function run({ goal, values = [], ops = {}, maxSteps = 30, minConfidence = 0, target } = {}) {
    if (!goal) throw new Error("run: `goal` is required");
    const history = [];
    const extraOps = Object.fromEntries(Object.entries(ops).map(([k, o]) => [k, o.description]));
    let unchanged = 0;
    for (let step = 0; step < maxSteps; step++) {
      const page = await observe(target);
      if (!page) {
        await sleep(200);
        continue;
      }
      const req = decisionRequest(page, goal, history, { extraOps, canType: values.length > 0 });
      const d = readDecision(await ask(req.state, req.questions, { caller: "run" }), req);
      const entry = { step, operation: d.operation, confidence: d.confidence, url: page.url };
      if (d.confidence < minConfidence) return { status: "uncertain", decision: d, history };
      if (d.operation === "DONE" || d.operation === "BLOCKED") {
        history.push(entry);
        return { status: d.operation.toLowerCase(), history };
      }
      let result;
      if (ops[d.operation]) {
        result = { ok: true, value: await ops[d.operation].run(page) };
        entry.action = d.operation;
        entry.kind = "op";
      } else {
        const a = d.action;
        let text;
        if (a.kind === "fill") {
          text =
            values.length === 1
              ? values[0]
              : (
                  await choose(
                    { goal, field: { label: a.label, value: a.value }, page: { title: page.title, text: page.text } },
                    VALUE,
                    values.map(String),
                    { caller: "run" }
                  )
                ).choice;
        }
        result = await act(a, page, { text, target });
        Object.assign(entry, { action: a.label, kind: a.kind, text });
        if (result?.stale) {
          entry.stale = result.stale;
          history.push(entry);
          continue;
        }
        await sleep(a.kind === "fill" ? 200 : 80);
      }
      entry.result = result?.value;
      const after = await observe(target).catch(() => null);
      // Compare actions too: typing/selecting changes values, not page text.
      entry.page_changed = !after || after.url !== page.url || after.text !== page.text ||
        JSON.stringify(after.actions) !== JSON.stringify(page.actions);
      history.push(entry);
      unchanged = entry.page_changed || entry.kind === "wait" ? 0 : unchanged + 1;
      if (unchanged >= 3) return { status: "stuck", history };
    }
    return { status: "max_steps", history };
  }

  return { ask, noul, choose, score, observe, act, run };
}

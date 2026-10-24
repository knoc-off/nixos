// browser-exec bridge: evaluate chrome JS sent over a unix-domain socket.
//
// Loaded as a *background module*, not a per-window *.uc.js. That distinction
// is the entire reason this file is reliable, so it is worth stating plainly:
// fx-autoconfig re-injects a classic *.uc.js into every chrome window, and a
// script that binds a socket as a side effect cannot survive that. The failure
// modes, both observed:
//
//   Without @onlyonce -- every new window unlinked the live socket file and
//   bound a fresh nsIServerSocket, orphaning the previous listener. Three
//   LISTEN entries on one path from one pid with a single window open.
//
//   With @onlyonce -- bound exactly once, in the *first* chrome window's JS
//   compartment. When that window closed the compartment was torn down and
//   the accept callback died with it, but the native nsIServerSocket kept the
//   path bound. The socket then accepted connections at the kernel level and
//   answered none: five ESTAB connections against a backlog of five, every
//   client hanging until its own timeout.
//
// A *.sys.mjs under chrome/JS is imported once per process via
// ChromeUtils.importESModule, into the shared system module global (see
// boot.sys.mjs: filename.endsWith(".sys.mjs") is sufficient, no header
// directive needed). That global outlives every window, so there is no
// compartment to die with and nothing to rebind. Closing all windows and
// opening a new one leaves the bridge answering throughout.
//
// This also means no window may be captured at load time. Everything below
// resolves its window per request and tolerates there being none at all --
// with the last window closed the bridge stays up and window-dependent
// helpers report that honestly instead of throwing an opaque null-deref.
//
// Protocol unchanged: one base64-encoded JS body per connection,
// newline-terminated. The reply is one line of JSON, then EOF. The body is
// wrapped in an async function, so bare `await`/`return` work.
//
// nsIServerSocket.initWithFilename is the same call DevTools' own socket
// server uses for its unix-domain listener (devtools/shared/security/socket.js):
// unlink any stale path, then bind with the given permissions.

// setTimeout is a window property, not a system-global one. In a *.uc.js this
// came free from the chrome window; here it has to be imported.
const { setTimeout } = ChromeUtils.importESModule(
  "resource://gre/modules/Timer.sys.mjs"
);

const SOCK_PATH = (() => {
  try {
    return Services.prefs.getStringPref("browserexec.socket");
  } catch (_) {
    const runtimeDir = Services.env.get("XDG_RUNTIME_DIR") || "/tmp";
    return runtimeDir + "/browser-exec/bridge.sock";
  }
})();

// Sidebery, the default `sidebarEval` target. Overridable via pref.
const DEFAULT_EXT_ID = "{3c078156-979c-498b-8990-85f7987dd929}";
const extensionId = () => {
  try {
    return Services.prefs.getStringPref("ucbridge.extensionId");
  } catch (_) {
    return DEFAULT_EXT_ID;
  }
};

// Window addressing.
//
// `getMostRecentWindow` alone cannot express "that other window" -- with two
// windows open every helper silently targeted whichever was focused last,
// which is a race when the caller is an agent rather than a human watching the
// screen. Each window therefore gets a stable numeric id (its browsing context
// id, which survives navigation and tab changes) and every helper takes an
// optional target.
const idOf = (obj) => {
  try {
    if (obj.browsingContext) return obj.browsingContext.id;
  } catch (_) {}
  try {
    return obj.docShell.browsingContext.id;
  } catch (_) {}
  return -1;
};

const allWins = () => {
  try {
    return Array.from(Services.wm.getEnumerator("navigator:browser"));
  } catch (_) {
    return [];
  }
};

// Resolve a window from an optional target. `null`/undefined means "most
// recent", a number means that window id. Returns null rather than throwing
// when there are no windows at all.
const getWin = (target) => {
  const id = target && typeof target === "object" ? target.window : target;
  if (id == null) {
    return Services.wm.getMostRecentWindow("navigator:browser");
  }
  return allWins().find((w) => idOf(w) === id) || null;
};

const needWin = (target) => {
  const win = getWin(target);
  if (!win) {
    throw new Error(
      target == null
        ? "no browser window open"
        : "no browser window with id " + JSON.stringify(target)
    );
  }
  return win;
};

const windows = () =>
  allWins().map((w) => ({
    id: idOf(w),
    title: w.document && w.document.title,
    tabs: w.gBrowser ? w.gBrowser.tabs.length : 0,
    active: w === Services.wm.getMostRecentWindow("navigator:browser"),
  }));

const tabsOf = (target) => {
  const wins = target == null ? allWins() : [needWin(target)];
  const out = [];
  for (const w of wins) {
    if (!w.gBrowser) continue;
    const windowId = idOf(w);
    for (const t of w.gBrowser.tabs) {
      out.push({
        id: idOf(t.linkedBrowser),
        // Same id under the key targets use, so a row from tabs() can be
        // passed straight to pageEval/selectTab/waitFor as a target.
        tab: idOf(t.linkedBrowser),
        window: windowId,
        url: t.linkedBrowser.currentURI.spec,
        title: t.label,
        selected: t.selected,
        // Epoch ms, and narrower than it looks: it tracks selection *within
        // a window*, not global focus. Firefox keeps bumping it on each
        // window's selected tab for as long as that tab stays selected, so
        // with N windows open all N selected tabs read as "now" no matter
        // which window you are actually in -- it cannot rank windows by
        // recency, only tabs inside one. Meaningful for ordering the
        // non-selected tabs of a given window; meaningless on a selected row.
        lastAccessed: t.lastAccessed,
        // A discarded tab has no live content process, so pageEval against it
        // resurrects the page (and re-runs its scripts) instead of reading
        // what was there. Worth seeing before targeting one.
        discarded: !!t.discarded,
        pinned: !!t.pinned,
        // Tabs hidden by a tab-group addon still show up here; they are
        // addressable but invisible to the user, which makes a write to one
        // of them surprising.
        hidden: !!t.hidden,
        audible: !!t.soundPlaying,
      });
    }
  }
  return out;
};

// Locate the <browser> hosting an extension's sidebar document, by URI
// rather than by id -- sidebar_action.default_panel is author-defined and
// Firefox recreates the inner element whenever the loaded URL changes, so a
// cached reference goes stale. Always re-resolve.
function findExtensionBrowser(win, extId) {
  if (!win) return null;
  const policy = WebExtensionPolicy.getByID(extId);
  if (!policy) return null;
  const base = policy.getURL();
  const matches = (b) => {
    try {
      return b.currentURI && b.currentURI.spec.startsWith(base);
    } catch (_) {
      return false;
    }
  };

  const outer = win.SidebarController && win.SidebarController.browser;
  if (outer) {
    try {
      const inner =
        outer.contentDocument &&
        outer.contentDocument.getElementById("webext-panels-browser");
      if (inner && matches(inner)) return inner;
    } catch (_) {}
  }

  const seen = new Set();
  const walk = (doc, depth) => {
    if (!doc || depth > 3 || seen.has(doc)) return null;
    seen.add(doc);
    for (const b of doc.querySelectorAll("browser")) {
      if (matches(b)) return b;
      let sub = null;
      try {
        sub = b.contentDocument;
      } catch (_) {}
      const hit = walk(sub, depth + 1);
      if (hit) return hit;
    }
    return null;
  };
  return walk(win.document, 0);
}

// Resolve the <browser> a page-level helper should target. A target of
// `{ tab: id }` addresses one specific tab in any window; a URL string or
// RegExp addresses the first tab whose URL matches (and is how a snippet
// pins "the page I opened" instead of racing the user's focus); a window id
// (bare number or `{ window: id }`) addresses that window's selected tab;
// nothing addresses the most recent window's selected tab.
const findTab = (pred) => {
  for (const w of allWins()) {
    if (!w.gBrowser) continue;
    for (const t of w.gBrowser.tabs) if (pred(t, w)) return { tab: t, win: w };
  }
  return null;
};

const urlMatches = (spec, m) =>
  m instanceof RegExp ? m.test(spec) : spec === m || spec.startsWith(m);

const targetBrowser = (target) => {
  if (typeof target === "string" || target instanceof RegExp) {
    const hit = findTab((t) => urlMatches(t.linkedBrowser.currentURI.spec, target));
    if (!hit) throw new Error("no tab matching " + String(target));
    return hit.tab.linkedBrowser;
  }
  if (target && typeof target === "object" && target.tab != null) {
    const hit = findTab((t) => idOf(t.linkedBrowser) === target.tab);
    if (!hit) throw new Error("no tab with id " + JSON.stringify(target.tab));
    return hit.tab.linkedBrowser;
  }
  const win = needWin(target);
  if (!win.gBrowser) throw new Error("window has no gBrowser");
  return win.gBrowser.selectedBrowser;
};

// How long a content probe may run before evalInBrowser gives up. Callers
// that know they need longer (a retry loop waiting on lazily-rendered DOM)
// pass their own; the opencode plugin derives it from the tool's `timeout`
// so a page-world snippet is never capped below what the caller asked for.
const CONTENT_TIMEOUT_MS = 8000;

// Wrap a user-supplied *statement body* for evaluation in a frame script.
// Pure string building, kept separate from the IPC so the shape below is
// readable and reviewable on its own.
//
// The body is evaluated with Cu.evalInSandbox in a sandbox whose prototype
// is the page's own window and `wantXrays: false`. That buys three things
// over a plain frame-script eval, each of which previously cost a debugging
// round-trip:
//
//   1. Every page global (`document`, `location`, `fetch`, ...) is in scope
//      via the prototype chain -- no hand-maintained alias list, no `with`.
//
//   2. No Xray wrappers: the body sees the page's real objects, so
//      `[...document.querySelectorAll(..)]`, page-defined globals and
//      framework internals all work like they would in the page's console.
//      (Through Xrays, spreading a NodeList throws "Permission denied to
//      access property Symbol.iterator" -- the single most common failure.)
//
//   3. `return` is optional. A body with no `return` is wrapped as an
//      expression first, so `document.title` alone yields the title; only
//      if that doesn't parse (a real multi-statement body) is it wrapped as
//      a function body. A syntax error in either form is caught and reported
//      *as a syntax error* instead of the probe silently timing out.
//
// Awaiting before sending matters: a pending Promise structured-clones to
// `{}` with no error, silently swallowing every async probe. A thrown error
// comes back tagged so the chrome side can reject rather than hand the
// caller a successful-looking result object (see receiveMessage).
//
// mode "frame" is the old behaviour, kept for internal callers that need it:
// the body runs in the frame script's own (system-principal) scope with the
// page reached through Xrays. readable() needs that for ChromeUtils, and
// jev needs it because its node cache lives on an Xray expando
// (window.__jevFast) -- expandos are per-compartment, so a fresh sandbox per
// call would lose the cache between observe() and act().
export const frameScriptFor = (code, id, mode = "page") => {
  const send =
    "sendAsyncMessage('bxdbg-result',{__id:" + JSON.stringify(id) + ",result:r})";
  if (mode === "frame") {
    return (
      "(async function(){var window=content,document=content.document;var r;" +
      "try{r=await (async function(){with(window){" +
      code +
      "\n}})()}catch(e){r={__bxError:String(e)}}" +
      send +
      "})()"
    );
  }
  // Expression form first (trailing `;` stripped so `document.title;` still
  // counts), statement-body form as the fallback. Compiling either does not
  // run it, so nothing executes twice.
  const expr = "(async function(){return (\n" + code.replace(/[\s;]+$/, "") + "\n)})";
  const body = "(async function(){\n" + code + "\n})";
  return (
    "(async function(){var r;try{var Cu=Components.utils;" +
    "var sb=Cu.Sandbox(content,{sandboxPrototype:content,wantXrays:false," +
    "sandboxName:'browser-exec:pageEval'});var fn;" +
    "try{fn=Cu.evalInSandbox(" + JSON.stringify(expr) + ",sb)}" +
    "catch(e1){try{fn=Cu.evalInSandbox(" + JSON.stringify(body) + ",sb)}" +
    "catch(e2){throw new Error('syntax error in page code: '+e2.message)}}" +
    "r=await fn();" +
    // Page objects (wantXrays:false) don't structured-clone reliably; a JSON
    // round-trip through the frame script's own JSON makes them plain data.
    "if(r&&typeof r==='object'){try{r=JSON.parse(JSON.stringify(r))}catch(_){r=String(r)}}" +
    "}catch(e){r={__bxError:String(e&&e.message||e)}}" +
    send +
    "})()"
  );
};

// Run code inside a remote <browser>'s content document via a frame-script
// round trip -- the only way to reach a process-separated document from
// chrome. Shared by sidebarEval, pageEval, readable and jev.
const evalInBrowser = (browserEl, code, timeoutMs, mode = "page") =>
  new Promise((resolve, reject) => {
    if (!browserEl) {
      reject(new Error("target browser not found"));
      return;
    }
    const mm = browserEl.messageManager;
    if (!mm) {
      reject(new Error("browser has no messageManager"));
      return;
    }
    const limit = Number(timeoutMs) > 0 ? Number(timeoutMs) : CONTENT_TIMEOUT_MS;
    const id = "p" + Date.now() + Math.random().toString(36).slice(2);
    const onMsg = {
      receiveMessage(m) {
        if (!m.data || m.data.__id !== id) return;
        mm.removeMessageListener("bxdbg-result", onMsg);
        const r = m.data.result;
        // An error in content must fail the call. Resolving with an error
        // *object* reports ok:true and buries the message in a result the
        // caller is busy destructuring -- so a typo in page code reads as a
        // successful probe that happened to find nothing. The content-side
        // stack is deliberately dropped: it is the frame script's own
        // data: URL, i.e. the percent-encoded source the caller just sent,
        // which is pages of noise carrying no information.
        if (r && typeof r === "object" && r.__bxError) {
          reject(new Error("error in content: " + r.__bxError));
          return;
        }
        resolve(r);
      },
    };
    mm.addMessageListener("bxdbg-result", onMsg);
    // Unique id in the URL doubles as a cache-buster; frame scripts are
    // keyed by URL and would otherwise be reused. The explicit charset is
    // load-bearing: a bare `data:,` script is decoded as Latin-1, so every
    // non-ASCII character in the code ("°", "ü") reached the page mangled.
    mm.loadFrameScript(
      "data:text/javascript;charset=utf-8," +
        encodeURIComponent(frameScriptFor(code, id, mode)),
      false
    );
    setTimeout(() => {
      try {
        mm.removeMessageListener("bxdbg-result", onMsg);
      } catch (e) {}
      // Page-mode syntax errors are caught and reported in content; a timeout
      // here means the code is still running (or, in frame mode only, failed
      // to parse).
      reject(new Error("page eval timed out after " + limit + "ms"));
    }, limit);
  });

// Evaluate in an extension's sidebar document (Sidebery by default). This
// used to be called `contentEval`, a name that read as "evaluate in the
// page" and sent people poking at a sidebar that had no idea what
// `document.getElementById('PartNo')` was. The page helper is `pageEval`.
const sidebarEval = (code, target, timeoutMs) =>
  evalInBrowser(
    findExtensionBrowser(getWin(target), extensionId()),
    code,
    timeoutMs
  );

const pageEval = (code, target, timeoutMs) =>
  evalInBrowser(targetBrowser(target), code, timeoutMs);

// Internal: old frame-scope semantics (see frameScriptFor). Not exposed to
// snippets.
const frameEval = (code, target, timeoutMs) =>
  evalInBrowser(targetBrowser(target), code, timeoutMs, "frame");

// Wait until a tab's document is loaded (and optionally until `selector`
// exists in it). The common pattern "openTab(); sleep(7000); probe" guesses
// at a delay and either wastes seconds or races the page; this polls.
const waitFor = async (target, { selector, timeout = 15000, interval = 250 } = {}) => {
  // A fresh tab is about:blank -- already "complete" -- before it navigates,
  // so a bare readyState check would return before the real page started.
  const notBlank = "location.href !== 'about:blank' && ";
  const probe = selector
    ? notBlank + "document.readyState !== 'loading' && !!document.querySelector(" + JSON.stringify(selector) + ")"
    : notBlank + "document.readyState === 'complete'";
  const deadline = Date.now() + timeout;
  for (;;) {
    let ok = false;
    try {
      ok = await pageEval(probe, target, 2000);
    } catch (_) {
      // document mid-navigation: try again
    }
    if (ok) return true;
    if (Date.now() > deadline) {
      throw new Error(
        "waitFor: timed out after " + timeout + "ms waiting for " + (selector || "load")
      );
    }
    await new Promise((r) => setTimeout(r, interval));
  }
};

// Article extraction via Firefox's own bundled Readability, on a page
// holding your real session. No dependency, no separate extraction lib.
// Import path varies across recent Firefox versions (moz-src:// vs
// resource://); try both.
const READABLE_SNIPPET = `
    let ReaderMode;
    try {
      ({ ReaderMode } = ChromeUtils.importESModule("moz-src:///toolkit/components/reader/ReaderMode.sys.mjs"));
    } catch (e) {
      ({ ReaderMode } = ChromeUtils.importESModule("resource://gre/modules/ReaderMode.sys.mjs"));
    }
    const article = await ReaderMode.parseDocument(content.document);
    if (!article) return null;
    return { title: article.title, byline: article.byline, textContent: article.textContent, length: article.length };
  `;
const readable = (target) => frameEval(READABLE_SNIPPET, target);

// A system-principal sandbox with no window prototype. Evaluating in the
// chrome window's own scope trips its CSP ("Missing 'unsafe-eval'"), and a
// sandbox taking the window as sandboxPrototype inherits that CSP too. A
// bare system-principal sandbox has no CSP, so helpers are injected by hand
// instead of arriving via the prototype chain.
const mkSandbox = () => {
  const s = Cu.Sandbox(Services.scriptSecurityManager.getSystemPrincipal(), {
    wantGlobalProperties: ["TextEncoder", "TextDecoder"],
  });
  const win = getWin();
  s.win = win;
  s.doc = win && win.document;
  s.Services = Services;
  s.Cc = Cc;
  s.Ci = Ci;
  s.Cu = Cu;
  s.ChromeUtils = ChromeUtils;
  s.WebExtensionPolicy = WebExtensionPolicy;
  s.setTimeout = setTimeout;
  try {
    s.InspectorUtils = InspectorUtils;
  } catch (e) {}
  s.sidebarEval = sidebarEval;
  // Hard failure, not a silent alias: the old name was the trap (see
  // sidebarEval's comment), so a stale snippet should fail loudly.
  s.contentEval = () => {
    throw new Error(
      "contentEval was removed: use pageEval(code, target?) for the page, " +
        "or sidebarEval(code) for the extension sidebar"
    );
  };
  s.pageEval = pageEval;
  s.waitFor = waitFor;
  s.sleep = (ms) => new Promise((r) => setTimeout(r, ms));
  s.readable = readable;
  s.sidebarBrowser = (id) => findExtensionBrowser(getWin(), id || extensionId());

  // Window addressing, exposed to snippets. `windows()` lists ids; every
  // other helper takes an optional target so a snippet can pin the window or
  // tab it means instead of racing whichever is focused.
  s.windows = windows;
  s.getWindow = (target) => getWin(target);
  s.tabs = tabsOf;
  // Open a tab and, unless {wait:false}, resolve once its document has
  // loaded. Returns a target usable by every page helper, so
  //   const t = await openTab(url); await pageEval("document.title", t)
  // addresses that tab no matter what the user clicks on meanwhile.
  s.openTab = async (url, opts = {}) => {
    const w = needWin(opts.window);
    const tab = w.gBrowser.addTab(url, {
      triggeringPrincipal: Services.scriptSecurityManager.getSystemPrincipal(),
    });
    if (opts.select !== false) w.gBrowser.selectedTab = tab;
    const target = { tab: idOf(tab.linkedBrowser), window: idOf(w), url };
    if (opts.wait !== false) {
      await waitFor(target, { selector: opts.selector, timeout: opts.timeout || 15000 });
    }
    return target;
  };
  // Bring an existing tab (by id, URL prefix or RegExp) to the front.
  s.selectTab = (target) => {
    const hit =
      typeof target === "string" || target instanceof RegExp
        ? findTab((t) => urlMatches(t.linkedBrowser.currentURI.spec, target))
        : findTab((t) => idOf(t.linkedBrowser) === (target && target.tab != null ? target.tab : target));
    if (!hit) throw new Error("selectTab: no tab matching " + String(target && target.tab != null ? target.tab : target));
    hit.win.gBrowser.selectedTab = hit.tab;
    hit.win.focus();
    return { tab: idOf(hit.tab.linkedBrowser), window: idOf(hit.win), url: hit.tab.linkedBrowser.currentURI.spec };
  };
  s.closeTab = (target) => {
    const hit =
      typeof target === "string" || target instanceof RegExp
        ? findTab((t) => urlMatches(t.linkedBrowser.currentURI.spec, target))
        : findTab((t) => idOf(t.linkedBrowser) === (target && target.tab != null ? target.tab : target));
    if (!hit) return false;
    hit.win.gBrowser.removeTab(hit.tab);
    return true;
  };

  // Window-scoped DOM helpers. Resolved against the target window at call
  // time, so they keep working after the window they last ran in is closed.
  s.$ = (q, target) => needWin(target).document.querySelector(q);
  s.$$ = (q, target) =>
    Array.from(needWin(target).document.querySelectorAll(q));
  s.cs = (e, target) => needWin(target).getComputedStyle(e);
  s.R = (e) => {
    if (!e) return null;
    const r = e.getBoundingClientRect();
    return {
      x: Math.round(r.x),
      y: Math.round(r.y),
      w: Math.round(r.width),
      h: Math.round(r.height),
    };
  };
  s.reloadUserscripts = async () => {
    try {
      const { ScriptStore } = ChromeUtils.importESModule(
        "chrome://userscripts/content/actor/store.sys.mjs"
      );
      return await ScriptStore.reload();
    } catch (e) {
      return { error: String(e) };
    }
  };
  // Jev decision engine (see jev.sys.mjs). Lazy getter so a broken jev
  // module can't take the whole bridge down with it.
  Object.defineProperty(s, "jev", {
    get: () =>
      ChromeUtils.importESModule("chrome://userscripts/content/jev.sys.mjs").makeJev(frameEval),
  });
  // Run a saved browser_exec snippet by name, in the world its header says.
  // Lets a script hand a reviewed snippet to jev.run({ops}) as an operation.
  s.snippet = async (name, target) => {
    if (!/^[A-Za-z0-9_-]+$/.test(name)) throw new Error("bad snippet name " + JSON.stringify(name));
    const src = await IOUtils.readUTF8(
      Services.env.get("HOME") + "/.local/share/browser-exec/snippets/" + name + ".js"
    );
    if (/^\/\/\s*world\s*=\s*"page"\s*$/m.test(src)) return pageEval(src, target);
    return runChrome(src);
  };
  return s;
};

// The wire carries base64 of UTF-8 bytes. atob alone yields one char per
// *byte* (Latin-1), so any non-ASCII text in a script ("42 °C", umlauts in a
// form value) arrived mangled. Decode the bytes as UTF-8 explicitly.
// atob is a window property in a *.uc.js and not reliably a system-global
// one: prefer the global, else borrow a window's.
const b64decode = (text) => {
  const raw =
    typeof atob === "function"
      ? atob(text)
      : getWin()
        ? getWin().atob(text)
        : null;
  if (raw == null) throw new Error("no base64 decoder available");
  return new TextDecoder().decode(Uint8Array.from(raw, (c) => c.charCodeAt(0)));
};

// Compile a chrome-world body: expression form first, so a bare
// `tabs().length` returns its value; statement-body form as the fallback.
// Same rule as page-world code (see frameScriptFor), so the two worlds can't
// disagree about whether `return` is needed.
const runChrome = (src) => {
  const sb = mkSandbox();
  let fn;
  try {
    fn = Cu.evalInSandbox("(async function(){return (\n" + src.replace(/[\s;]+$/, "") + "\n)})", sb);
  } catch (_) {
    fn = Cu.evalInSandbox("(async function(){\n" + src + "\n})", sb);
  }
  return fn();
};

function handleConnection(transport) {
  const rawIn = transport
    .openInputStream(0, 0, 0)
    .QueryInterface(Ci.nsIAsyncInputStream);
  const output = transport.openOutputStream(
    Ci.nsITransport.OPEN_BLOCKING,
    0,
    0
  );
  const sin = Cc["@mozilla.org/scriptableinputstream;1"].createInstance(
    Ci.nsIScriptableInputStream
  );
  sin.init(rawIn);
  const mainThread = Services.tm.mainThread;
  let buf = "";

  const respond = async (line) => {
    let payload;
    try {
      const value = await runChrome(b64decode(line.trim()));
      payload =
        value === undefined
          ? { ok: true, value: null, note: "script returned undefined (missing `return`?)" }
          : { ok: true, value };
    } catch (e) {
      payload = { ok: false, error: String(e) };
      // Bridge-internal frames are pure noise (every error "comes from"
      // respond/onInputStreamReady); keep only frames from the caller's code.
      const own = String((e && e.stack) || "")
        .split("\n")
        .filter((l) => l && !/bridge\.sys\.mjs/.test(l));
      if (own.length) payload.stack = own.join("\n");
    }

    let text;
    try {
      text =
        JSON.stringify(payload, null, 2) ??
        '{"ok":true,"value":"<undefined>"}';
    } catch (e) {
      text = JSON.stringify({
        ok: false,
        error: "unserialisable result: " + String(e),
      });
    }

    try {
      const conv = Cc[
        "@mozilla.org/intl/converter-output-stream;1"
      ].createInstance(Ci.nsIConverterOutputStream);
      conv.init(output, "UTF-8");
      conv.writeString(text + "\n");
      conv.close(); // closes the output half, signalling EOF to the client
    } catch (e) {}
    try {
      rawIn.close();
    } catch (e) {}
  };

  const waiter = {
    onInputStreamReady() {
      let avail = 0;
      try {
        avail = sin.available();
      } catch (e) {
        try {
          rawIn.close();
        } catch (_) {}
        return;
      }
      if (avail) buf += sin.read(avail);
      const nl = buf.indexOf("\n");
      if (nl >= 0) {
        respond(buf.slice(0, nl));
        return;
      }
      rawIn.asyncWait(waiter, 0, 0, mainThread);
    },
  };
  rawIn.asyncWait(waiter, 0, 0, mainThread);
}

// Bind and start accepting. Kept as a named function so onStopListening can
// retry it: an accept loop that stops for any reason other than shutdown is
// indistinguishable from the hang this module exists to avoid.
let stopping = false;
let rebinds = 0;

function listen() {
  const socket = Cc["@mozilla.org/network/server-socket;1"].createInstance(
    Ci.nsIServerSocket
  );
  try {
    const file = Cc["@mozilla.org/file/local;1"].createInstance(Ci.nsIFile);
    // Parent dir has to exist -- initWithFilename does not mkdir -p.
    const parent = Cc["@mozilla.org/file/local;1"].createInstance(Ci.nsIFile);
    parent.initWithPath(SOCK_PATH.slice(0, SOCK_PATH.lastIndexOf("/")));
    if (!parent.exists()) parent.create(Ci.nsIFile.DIRECTORY_TYPE, 0o700);
    file.initWithPath(SOCK_PATH);
    if (file.exists()) file.remove(false); // stale node from a prior run
    socket.initWithFilename(file, 0o600, -1);
  } catch (e) {
    console.error("browser-exec: failed to bind " + SOCK_PATH + ": " + e);
    return;
  }

  socket.asyncListen({
    onSocketAccepted(serv, transport) {
      // One malformed connection must not take down the listener for the rest
      // of the session -- an exception thrown out of onSocketAccepted would
      // leave the socket bound and unserviced.
      try {
        handleConnection(transport);
      } catch (e) {
        console.error("browser-exec: connection handler failed: " + e);
      }
    },
    onStopListening(serv, status) {
      if (stopping) return;
      console.warn("browser-exec: listener stopped, status " + status);
      if (rebinds++ < 3) setTimeout(listen, 1000);
    },
  });

  // Shutdown is the one stop that must not trigger a rebind.
  Services.obs.addObserver(
    {
      observe() {
        stopping = true;
        try {
          socket.close();
        } catch (e) {}
      },
    },
    "quit-application-granted"
  );

  console.log("browser-exec: listening on unix:" + SOCK_PATH);
}

listen();

// browser-exec bridge: evaluate chrome JS sent over a unix-domain socket.
//
// Supersedes the old debug-bridge.uc.js (loopback TCP, port 12345). Same
// framing and sandbox, two differences:
//
//   1. Transport is a unix socket at $XDG_RUNTIME_DIR/browser-exec/bridge.sock,
//      mode 0600. A TCP loopback socket is reachable by anything on the
//      machine that can open a socket; page JS in particular is blocked only
//      by accident (fetch/WebSocket can't produce a bare-base64 first line,
//      so `atob` throws and `src` stays "" -- true today, undocumented, and
//      one framing change from false). A filesystem-permission-protected
//      socket is unauthenticated by the same accident-of-protocol argument
//      *and* invisible to page content, which has no API that reaches the
//      filesystem namespace at all.
//   2. Adds `pageEval` (bound to the active tab, not just the sidebar
//      extension frame) and a handful of DOM helpers geared at extraction
//      rather than UI probing.
//
// Protocol unchanged: one base64-encoded JS body per connection,
// newline-terminated. The reply is one line of JSON, then EOF. The body is
// wrapped in an async function, so bare `await`/`return` work.
//
// nsIServerSocket.initWithFilename is the same call DevTools' own socket
// server uses for its unix-domain listener (devtools/shared/security/socket.js):
// unlink any stale path, then bind with the given permissions. onSocketAccepted
// hands back the same nsISocketTransport either way, so the accept loop below
// is unchanged from the TCP version.
(function () {
  const SOCK_PATH = (() => {
    try {
      return Services.prefs.getStringPref("browserexec.socket");
    } catch (_) {
      const runtimeDir =
        Services.env.get("XDG_RUNTIME_DIR") || "/tmp";
      return runtimeDir + "/browser-exec/bridge.sock";
    }
  })();

  // Sidebery, kept as the default `contentEval` target for backward
  // compatibility with existing zdbg-style scripts. Overridable via pref.
  const DEFAULT_EXT_ID = "{3c078156-979c-498b-8990-85f7987dd929}";
  const extensionId = () => {
    try {
      return Services.prefs.getStringPref("ucbridge.extensionId");
    } catch (_) {
      return DEFAULT_EXT_ID;
    }
  };

  const getWin = () => Services.wm.getMostRecentWindow("navigator:browser");

  // Locate the <browser> hosting an extension's sidebar document, by URI
  // rather than by id -- sidebar_action.default_panel is author-defined and
  // Firefox recreates the inner element whenever the loaded URL changes, so a
  // cached reference goes stale. Always re-resolve.
  function findExtensionBrowser(win, extId) {
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
      } catch (_) { }
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
        } catch (_) { }
        const hit = walk(sub, depth + 1);
        if (hit) return hit;
      }
      return null;
    };
    return walk(win.document, 0);
  }

  // Run code inside a remote <browser>'s content document via a frame-script
  // round trip -- the only way to reach a process-separated document from
  // chrome. Shared by contentEval (sidebar) and pageEval (active tab).
  const evalInBrowser = (browserEl, code) =>
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
      const id = "p" + Date.now() + Math.random().toString(36).slice(2);
      const onMsg = {
        receiveMessage(m) {
          if (m.data && m.data.__id === id) {
            mm.removeMessageListener("bxdbg-result", onMsg);
            resolve(m.data.result);
          }
        },
      };
      mm.addMessageListener("bxdbg-result", onMsg);
      // Unique id in the URL doubles as a cache-buster; frame scripts are
      // keyed by URL and would otherwise be reused.
      //
      // The async wrapper lets `code` use bare await/return, and the outer
      // IIFE awaits before sending: a pending Promise structured-clones to
      // `{}` with no error, which silently swallows every async probe until
      // that's caught.
      // Frame scripts get `content` (the tab's window) as their only content
      // global -- there is no bare `document`/`window`, which is why naive
      // page-JS (`document.querySelectorAll(...)`) throws "document is not
      // defined" here even though it's exactly what pageEval is for. Alias
      // them so callers can write ordinary DOM code instead of learning this
      // wrapper's internals.
      const inner =
        "(async function(){var window=content,document=content.document;var r;try{r=await (async function(){" +
        code +
        "})()}catch(e){r={__error:String(e),stack:e.stack}}" +
        "sendAsyncMessage('bxdbg-result',{__id:'" +
        id +
        "',result:r})})()";
      mm.loadFrameScript("data:," + encodeURIComponent(inner), false);
      setTimeout(() => {
        try {
          mm.removeMessageListener("bxdbg-result", onMsg);
        } catch (e) { }
        reject(new Error("content probe timed out"));
      }, 8000);
    });

  const contentEval = (code) =>
    evalInBrowser(findExtensionBrowser(getWin(), extensionId()), code);

  const pageEval = (code) => {
    const win = getWin();
    const browserEl = win && win.gBrowser && win.gBrowser.selectedBrowser;
    return evalInBrowser(browserEl, code);
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
  const readable = () => pageEval(READABLE_SNIPPET);

  // A system-principal sandbox with no window prototype. Evaluating in the
  // chrome window's own scope trips its CSP ("Missing 'unsafe-eval'"), and a
  // sandbox taking the window as sandboxPrototype inherits that CSP too. A
  // bare system-principal sandbox has no CSP, so helpers are injected by hand
  // instead of arriving via the prototype chain.
  const mkSandbox = () => {
    const win = getWin();
    const s = Cu.Sandbox(Services.scriptSecurityManager.getSystemPrincipal(), {
      wantGlobalProperties: ["TextEncoder", "TextDecoder"],
    });
    s.win = win;
    s.doc = win.document;
    s.Services = Services;
    s.Cc = Cc;
    s.Ci = Ci;
    s.Cu = Cu;
    s.ChromeUtils = ChromeUtils;
    s.WebExtensionPolicy = WebExtensionPolicy;
    s.setTimeout = win.setTimeout.bind(win);
    try {
      s.InspectorUtils = InspectorUtils;
    } catch (e) { }
    s.contentEval = contentEval;
    s.pageEval = pageEval;
    s.readable = readable;
    s.sidebarBrowser = (id) => findExtensionBrowser(getWin(), id || extensionId());
    s.$ = (q) => win.document.querySelector(q);
    s.$$ = (q) => Array.from(win.document.querySelectorAll(q));
    s.cs = (e) => win.getComputedStyle(e);
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
    s.tabs = () =>
      Array.from(win.gBrowser.tabs).map((t) => ({
        url: t.linkedBrowser.currentURI.spec,
        title: t.label,
        selected: t.selected,
      }));
    s.openTab = (url) => {
      const tab = win.gBrowser.addTab(url, {
        triggeringPrincipal: Services.scriptSecurityManager.getSystemPrincipal(),
      });
      win.gBrowser.selectedTab = tab;
      return { url };
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
    return s;
  };

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
        let src = "";
        try {
          src = getWin().atob(line.trim());
        } catch (e) { }

        let payload;
        try {
          let value = Cu.evalInSandbox(
            "(async function(){\n" + src + "\n})()",
            mkSandbox()
          );
          value = await value;
          payload = { ok: true, value };
        } catch (e) {
          payload = { ok: false, error: String(e), stack: e && e.stack };
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
        } catch (e) { }
        try {
          rawIn.close();
        } catch (e) { }
      };

      const waiter = {
        onInputStreamReady() {
          let avail = 0;
          try {
            avail = sin.available();
          } catch (e) {
            try {
              rawIn.close();
            } catch (_) { }
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
    },
    onStopListening() { },
  });

  console.log("browser-exec: listening on unix:" + SOCK_PATH);
})();

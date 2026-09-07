// Debug bridge: evaluate chrome JS sent over a loopback TCP socket.
//
// Ported from the Zen setup to native Firefox. The socket, sandbox and framing
// are unchanged; what differs is how the extension's sidebar document is
// reached (see findExtensionBrowser).
//
// Protocol: one base64-encoded JS body per connection, newline-terminated. The
// reply is one line of JSON, then EOF. The body is wrapped in an async function,
// so bare `await` and `return` work.
//
// Loopback-only and unauthenticated: anything that can open a socket to
// 127.0.0.1:PORT gets chrome-privileged eval. A development tool, not something
// to leave enabled on a machine you do not trust.
(function () {
  const PORT = 12345;

  // Sidebery. Overridable via pref so the bridge can target another
  // extension's sidebar without editing this file.
  const DEFAULT_EXT_ID = "{3c078156-979c-498b-8990-85f7987dd929}";
  const extensionId = () => {
    try {
      return Services.prefs.getStringPref("ucbridge.extensionId");
    } catch (_) {
      return DEFAULT_EXT_ID;
    }
  };

  const getWin = () => Services.wm.getMostRecentWindow("navigator:browser");

  // Locate the <browser> hosting an extension's sidebar document.
  //
  // Under Zen this was a single getElementById("sidebery"), because the
  // integration script built that element itself. Native Firefox nests two
  // browsers: SidebarController.browser is #sidebar, a chrome frame holding
  // webext-panels.xhtml, and the extension page lives in
  // #webext-panels-browser *inside* that document.
  //
  // Matching is by URI rather than by id: sidebar_action.default_panel is
  // author-defined, and Firefox destroys and recreates the inner element
  // whenever the loaded extension URL changes (loadPanel() removes the whole
  // stack), so a cached reference goes stale. Always re-resolve.
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

    // Fast path: the documented nesting.
    const outer = win.SidebarController && win.SidebarController.browser;
    if (outer) {
      try {
        const inner =
          outer.contentDocument &&
          outer.contentDocument.getElementById("webext-panels-browser");
        if (inner && matches(inner)) return inner;
      } catch (_) { }
    }

    // Fallback: walk every <browser> in the chrome document, descending into
    // nested chrome documents. Survives internal id renames and the
    // sidebar.revamp split.
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

  // Run code inside the extension's sidebar document. That frame is remote, so
  // its document is in another process and unreachable from chrome except by
  // round-tripping a frame script.
  const contentEval = (code) =>
    new Promise((resolve, reject) => {
      const el = findExtensionBrowser(getWin(), extensionId());
      if (!el) {
        reject(
          new Error(
            "extension sidebar browser not found -- is the sidebar open?"
          )
        );
        return;
      }
      const mm = el.messageManager;
      if (!mm) {
        reject(new Error("sidebar browser has no messageManager"));
        return;
      }
      const id = "p" + Date.now() + Math.random().toString(36).slice(2);
      const onMsg = {
        receiveMessage(m) {
          if (m.data && m.data.__id === id) {
            mm.removeMessageListener("zdbg-result", onMsg);
            resolve(m.data.result);
          }
        },
      };
      mm.addMessageListener("zdbg-result", onMsg);
      // Unique id in the URL doubles as a cache-buster; frame scripts are keyed
      // by URL and would otherwise be reused.
      //
      // The async wrapper lets `code` use bare await/return, and the outer IIFE
      // awaits before sending: a pending Promise structured-clones to `{}` with
      // no error, which silently swallowed every async probe until that was
      // caught.
      const inner =
        "(async function(){var r;try{r=await (async function(){" +
        code +
        "})()}catch(e){r={__error:String(e),stack:e.stack}}" +
        "sendAsyncMessage('zdbg-result',{__id:'" +
        id +
        "',result:r})})()";
      mm.loadFrameScript("data:," + encodeURIComponent(inner), false);
      setTimeout(() => {
        try {
          mm.removeMessageListener("zdbg-result", onMsg);
        } catch (e) { }
        reject(new Error("content probe timed out"));
      }, 8000);
    });

  // A system-principal sandbox with no window prototype. Evaluating in the
  // chrome window's own scope trips its CSP ("Missing 'unsafe-eval'"), and a
  // sandbox taking the window as sandboxPrototype inherits that CSP too. A bare
  // system-principal sandbox has no CSP, so helpers are injected by hand
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
    // Locate the sidebar browser from a probe, for inspecting the frame itself
    // rather than its content.
    s.sidebarBrowser = (id) => findExtensionBrowser(getWin(), id || extensionId());
    s.$ = (q) => win.document.querySelector(q);
    s.$$ = (q) => Array.from(win.document.querySelectorAll(q));
    s.cs = (e) => win.getComputedStyle(e);
    // Rects rounded to whole pixels -- sub-pixel noise obscures the comparisons
    // that matter here (does this box have a width, is it on screen).
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
    return s;
  };

  const socket = Cc["@mozilla.org/network/server-socket;1"].createInstance(
    Ci.nsIServerSocket
  );
  try {
    socket.init(PORT, true, -1);
  } catch (e) {
    // Port already bound: another window's copy owns it. Nothing to do.
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
          // Closing the output half signals EOF, which is how the client knows
          // the reply is complete.
          conv.close();
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
            // Peer went away mid-request.
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

  console.log("fx-dbg: listening on 127.0.0.1:" + PORT);
})();

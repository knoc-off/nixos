// TEMPORARY DEBUGGING TOOL -- NOT FOR COMMIT.
//
// Opens a loopback-only TCP socket on 127.0.0.1:12345 that evaluates chrome
// JavaScript and returns the result as JSON. Its only reason to exist is that
// the Sidebery sidebar is a *remote* <browser>, so the interesting state (which
// CSS rules matched, what the tabs actually measure) lives in a content process
// that cannot be inspected from a config file. Pasting probes into the Browser
// Console by hand works, but the sidebar's collapsed state is decided at startup
// and Sidebery is injected exactly once per launch, so testing it properly means
// restarting Zen repeatedly -- and every restart would otherwise mean another
// manual paste.
//
// Protocol: send one line of base64-encoded JS terminated by "\n"; receive one
// line of JSON, `{ok, value}` or `{ok:false, error}`. The body is wrapped in an
// async function, so `await` and `return` both work.
//
// Base64-on-one-line rather than the obvious "send raw JS until EOF": reading
// until EOF means the client has to half-close its write side, and letting
// NetUtil.asyncFetch consume the input stream tears down the socket transport
// when it completes -- often before the reply has flushed, which lost roughly a
// third of all responses. Framing on a newline instead means neither side ever
// half-closes, and base64 guarantees the payload contains no newline of its own.
//
// Security notes:
//   - Bound loopback-only (nsIServerSocket.init(port, /* loopbackOnly */ true)),
//     so nothing outside this machine can reach it.
//   - It still evaluates arbitrary code with chrome privileges for any local
//     process. That is fine for a debugging session on a machine you control and
//     unacceptable to leave enabled afterwards.
//   - Remove this file and its entry in default.nix once the sidebar work is
//     done. It is deliberately not referenced from any committed config.
//
// If the port is already taken (another window got here first, or a hand-pasted
// bridge is live), init() throws and we bail -- that doubles as the singleton
// guard, since fx-autoconfig runs this once per chrome window.

(() => {
  const PORT = 12345;

  const getWin = () => Services.wm.getMostRecentWindow("navigator:browser");

  // Run code inside the remote Sidebery content document and resolve with its
  // return value. This is the whole point of the bridge: `#sidebery` is
  // remote="true", so its document is in another process and unreachable from
  // chrome except by round-tripping a frame script.
  const contentEval = (code) =>
    new Promise((resolve, reject) => {
      const el = getWin().document.getElementById("sidebery");
      if (!el) {
        reject(new Error("#sidebery not found"));
        return;
      }
      const mm = el.messageManager;
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
      // async wrapper so `code` may itself use bare `await`/`return`, and the
      // outer IIFE awaits the result before sending it -- a pending Promise
      // structured-clones to `{}` with no error, which silently swallowed
      // every async probe until this was caught.
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
        } catch (e) {}
        reject(new Error("content probe timed out"));
      }, 8000);
    });

  // A system-principal sandbox with no window prototype. Evaluating in the
  // chrome window's own scope trips its CSP ("Missing 'unsafe-eval'"), and a
  // sandbox that takes the window as sandboxPrototype inherits that CSP too.
  // A bare system-principal sandbox has no CSP, so helpers get injected by hand
  // instead of coming in via the prototype chain.
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
    s.setTimeout = win.setTimeout.bind(win);
    try {
      s.InspectorUtils = InspectorUtils;
    } catch (e) {}
    s.contentEval = contentEval;
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
      const sin = Cc[
        "@mozilla.org/scriptableinputstream;1"
      ].createInstance(Ci.nsIScriptableInputStream);
      sin.init(rawIn);
      const mainThread = Services.tm.mainThread;
      let buf = "";

      const respond = async (line) => {
        let src = "";
        try {
          src = getWin().atob(line.trim());
        } catch (e) {}

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
            // Peer went away mid-request.
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
    },
    onStopListening() {},
  });

  console.log("zen-dbg: listening on 127.0.0.1:" + PORT);
})();

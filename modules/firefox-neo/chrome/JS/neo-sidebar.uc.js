// Dedicated Sidebery sidebar.
//
// Firefox's revamp sidebar is ONE panel with a swappable occupant: #sidebar is
// a single <browser> whose src gets rewritten as you switch tools, and every
// entry in the `sidebar.main.tools` pref competes for it. Installing Bitwarden
// or flipping on the built-in AI chat is enough to evict Sidebery from the
// space where your tabs live -- measured: SidebarController.currentID flipping
// to "viewGenaiChatSidebar" with #sidebar pointing at genai/chat.html while
// Sidebery was simply gone.
//
// So this builds a second sidebar that nothing else can take. It is NOT the
// Zen-style reparenting the rest of this module was written to avoid: nothing
// is moved out of the native sidebar, and SidebarController is not patched or
// hooked. We create our own <browser> and load Sidebery's sidebar_action
// default_panel URL into it directly. The native sidebar is left completely
// alone and stays available for Bitwarden et al.
//
// The cost of not going through SidebarController: the sidebarAction WebExt
// API (setPanel/open/close, badges) is not wired to this frame. Sidebery is a
// self-contained panel and does not appear to care, but that is the first
// thing to suspect if it ever misbehaves.

(function () {
  const SIDEBERY_ID = "{3c078156-979c-498b-8990-85f7987dd929}";
  const BOX_ID = "neo-sidebar-box";
  const BROWSER_ID = "neo-sidebar";
  const TOOLS_PREF = "sidebar.main.tools";

  // Sidebery's manifest sets sidebar_action.open_at_install, so Firefox keeps
  // re-registering it as a native sidebar tool -- it appends the id back onto
  // sidebar.main.tools, and you get two Sidebery instances: ours in the rail
  // plus one Firefox auto-opens in the native panel.
  //
  // open_at_install is in the manifest, not in Sidebery's own settings, so
  // there is nothing to turn off on the extension side. And stripping the pref
  // once at startup is not enough either -- that was tried, and Firefox
  // re-adds it *after* we run. Hence the observer below: strip on every write,
  // whenever it happens, rather than trying to guess the right moment.
  function stripTool() {
    const tools = Services.prefs.getStringPref(TOOLS_PREF, "");
    const kept = tools
      .split(",")
      .map((s) => s.trim())
      .filter((s) => s && s !== SIDEBERY_ID);
    if (kept.join(",") === tools) return false;
    Services.prefs.setStringPref(TOOLS_PREF, kept.join(","));
    return true;
  }

  function unregisterNativeTool(win) {
    try {
      stripTool();
      // Already opened by the time we got here -- close it, otherwise the
      // duplicate stays up for this session. currentID for an extension
      // sidebar is "_<uuid-without-braces>_-sidebar-action".
      const sc = win.SidebarController;
      const bare = SIDEBERY_ID.slice(1, -1);
      if (sc && sc.isOpen && String(sc.currentID).includes(bare)) {
        sc.hide();
      }
    } catch (e) {
      console.error("neo-sidebar: could not unregister native tool", e);
    }
  }

  // Keep it stripped. setStringPref inside the observer re-enters, but the
  // second pass is a no-op (kept === tools) so it settles immediately.
  function watchToolsPref(win) {
    const obs = { observe: () => unregisterNativeTool(win) };
    try {
      Services.prefs.addObserver(TOOLS_PREF, obs);
      win.addEventListener("unload", () => {
        try {
          Services.prefs.removeObserver(TOOLS_PREF, obs);
        } catch (_) { }
      }, { once: true });
    } catch (e) {
      console.error("neo-sidebar: pref observer failed", e);
    }
  }


  // The moz-extension:// origin is a per-profile random UUID, so the panel URL
  // cannot be hardcoded -- it has to be resolved from the live policy.
  function panelURL() {
    const policy = WebExtensionPolicy.getByID(SIDEBERY_ID);
    if (!policy) return null;
    const panel =
      policy.extension &&
      policy.extension.manifest &&
      policy.extension.manifest.sidebar_action &&
      policy.extension.manifest.sidebar_action.default_panel;
    // default_panel is already absolute in the resolved manifest, but fall
    // back to the documented path in case that changes.
    return panel || policy.getURL("sidebar/sidebar.html");
  }

  function build(win) {
    const doc = win.document;
    if (doc.getElementById(BOX_ID)) return true;

    const url = panelURL();
    if (!url) return false;

    const anchor = doc.getElementById("sidebar-box");
    if (!anchor || !anchor.parentElement) return false;

    const box = doc.createXULElement("vbox");
    box.id = BOX_ID;

    const browser = doc.createXULElement("browser");
    browser.id = BROWSER_ID;
    // webext-browsers + the extension view type are what get this loaded into
    // the extension content process rather than a plain web one; without them
    // the moz-extension:// URL is not allowed to load.
    browser.setAttribute("type", "content");
    browser.setAttribute("remote", "true");
    browser.setAttribute("maychangeremoteness", "true");
    browser.setAttribute("webextension-view-type", "sidebar");
    browser.setAttribute("messagemanagergroup", "webext-browsers");
    browser.setAttribute("context", "contentAreaContextMenu");
    browser.setAttribute("disablehistory", "true");
    browser.setAttribute("disablefullscreen", "true");
    box.appendChild(browser);

    // Before #sidebar-box, so ours is the leftmost panel.
    anchor.parentElement.insertBefore(box, anchor);

    const principal = Services.scriptSecurityManager.getSystemPrincipal();
    try {
      if (browser.fixupAndLoadURIString) {
        browser.fixupAndLoadURIString(url, { triggeringPrincipal: principal });
      } else {
        browser.loadURI(Services.io.newURI(url), {
          triggeringPrincipal: principal,
        });
      }
    } catch (e) {
      console.error("neo-sidebar: failed to load panel", e);
      box.remove();
      return false;
    }
    return true;
  }

  // Push the window's focus state into the sidebar frame.
  //
  // The chrome swaps --lwt-accent-color (active) for
  // --lwt-accent-color-inactive when the window loses focus, and
  // sidebery-collapse.css follows that for the rail via :-moz-window-inactive.
  // Sidebery's header cannot: it lives inside the extension frame, a separate
  // content process, where neither the chrome's custom properties nor that
  // pseudo-class are visible. So the state is mirrored in as a plain attribute
  // on <html>, and chrome/CSS/sidebery.css keys the header colour off it.
  //
  // A frame script rather than insertCSS: the values have to change per focus
  // event, and this only touches one attribute rather than re-injecting a
  // sheet each time. Note the frame gets no WebExtension `browser` API, so
  // going through Sidebery's own storage is not an option here.
  const FOCUS_FRAME_SCRIPT =
    "data:application/javascript;charset=utf-8," +
    encodeURIComponent(`
      addMessageListener("neo-sidebar:focus", (msg) => {
        const el = content && content.document && content.document.documentElement;
        if (!el) return;
        if (msg.data.active) {
          el.setAttribute("neo-window-active", "true");
        } else {
          el.removeAttribute("neo-window-active");
        }
      });
    `);

  function watchFocus(win) {
    const browser = win.document.getElementById(BROWSER_ID);
    if (!browser) return;

    // Look the message manager up on every use rather than caching it. Cheap,
    // and it cannot go stale if the frame loader is ever swapped out.
    const getMM = () => browser.messageManager;

    const send = () => {
      try {
        const mm = getMM();
        if (!mm) return;
        // :-moz-window-inactive, NOT Services.focus.activeWindow.
        //
        // activeWindow still points at this window while the deactivate event
        // is being dispatched, so the obvious predicate reports "focused" on
        // the way out and the panel never leaves the active colour. Measured
        // across six transitions: activeWindow === win was true on every
        // deactivate, while the pseudo-class was correct every time.
        //
        // It also has to be this, not a focus API, for a second reason: the
        // rail is styled by :-moz-window-inactive, and if the panel disagrees
        // with it the two halves recolour out of step at the seam.
        const active = !win.document.documentElement.matches(
          ":-moz-window-inactive",
        );
        mm.sendAsyncMessage("neo-sidebar:focus", { active });
      } catch (e) {
        // Frame may be mid-teardown; nothing useful to do.
      }
    };

    // Register the listener, then seed the current state -- but seed twice.
    //
    // The frame script itself lands reliably at STATE_STOP. The seeding send()
    // does not: at that moment the extension's document is still coming up, and
    // a message delivered before it is ready is accepted and dropped. Nothing
    // errors, the listener stays alive, and the panel simply sits on the
    // default colour until some later focus change happens to push the state.
    //
    // Measured directly: send at STATE_STOP -> attribute stays null; the exact
    // same send a few hundred ms later -> attribute set and #root computes to
    // rgb(27,36,41). Hence the delayed repeat. It is idempotent -- worst case
    // it re-sets the value it already had.
    const register = () => {
      try {
        const mm = getMM();
        if (!mm) return;
        mm.loadFrameScript(FOCUS_FRAME_SCRIPT, false);
        send();
        win.setTimeout(send, 300);
      } catch (e) {
        // Frame mid-teardown; a later trigger will retry.
      }
    };

    const progress = {
      QueryInterface: ChromeUtils.generateQI([
        "nsIWebProgressListener",
        "nsISupportsWeakReference",
      ]),
      onStateChange(webProgress, request, flags) {
        const done = Ci.nsIWebProgressListener.STATE_STOP;
        const network = Ci.nsIWebProgressListener.STATE_IS_NETWORK;
        if (webProgress.isTopLevel && flags & done && flags & network) {
          register();
        }
      },
    };

    try {
      browser.addProgressListener(
        progress,
        Ci.nsIWebProgress.NOTIFY_STATE_ALL,
      );
    } catch (e) {
      console.error("neo-sidebar: progress listener failed", e);
    }

    // Re-register per document: a new document means a new frame loader, and
    // the listener does not survive it.
    if (browser.browsingContext?.currentWindowGlobal) register();

    win.addEventListener("activate", send);
    win.addEventListener("deactivate", send);

    // No re-seed hook after a frame reload: the delayedLoad=true registration
    // re-runs the script in the new document, and the next focus change pushes
    // the state. A reloaded frame can therefore sit on the default colour until
    // the window is next focused or blurred. Not worth more machinery -- the
    // obvious hook, a "load" listener on the browser element, does not fire for
    // this remote frame anyway (measured: zero events across a full reload).

    // Seed the current state: the frame may load already focused, in which
    // case no activate event is coming.
    send();

    win.addEventListener(
      "unload",
      () => {
        win.removeEventListener("activate", send);
        win.removeEventListener("deactivate", send);
      },
      { once: true },
    );
  }

  function init(win) {
    watchToolsPref(win);
    unregisterNativeTool(win);
    if (build(win)) {
      watchFocus(win);
      return;
    }
    // The extension may not be started yet on a cold profile. Retry on the
    // extension-ready notification rather than polling.
    const obs = {
      observe() {
        unregisterNativeTool(win);
        if (build(win)) {
          watchFocus(win);
          Services.obs.removeObserver(obs, "webextension-ready");
        }
      },
    };
    try {
      Services.obs.addObserver(obs, "webextension-ready");
      win.addEventListener("unload", () => {
        try {
          Services.obs.removeObserver(obs, "webextension-ready");
        } catch (_) { }
      }, { once: true });
    } catch (e) {
      console.error("neo-sidebar: observer registration failed", e);
    }
  }

  if (document.readyState === "complete") {
    init(window);
  } else {
    window.addEventListener("load", () => init(window), { once: true });
  }
})();

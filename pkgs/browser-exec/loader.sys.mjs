// browser-exec userscript loader.
//
// Top-level *.sys.mjs under chrome/JS -- fx-autoconfig's boot.sys.mjs marks any
// top-level *.sys.mjs as a "background module" and imports it once at startup
// (see boot.sys.mjs's ScriptData#inbackground: filename.endsWith(".sys.mjs")
// is sufficient, no @backgroundmodule header needed). This file's only job at
// import time is registering the actor below.
//
// Deliberately NOT using fx-autoconfig's own "@WindowActor" script-header
// mechanism (documented in its readme's Experimental namespace): that path
// is gated behind the userChromeJS.experimental.enabled pref and described as
// "likely unfinished, untested". ChromeUtils.registerWindowActor is a stable
// platform API and calling it directly avoids depending on an experimental
// feature flag for something this central.
try {
  ChromeUtils.registerWindowActor("BrowserExecUserscript", {
    parent: {
      esModuleURI:
        "chrome://userscripts/content/actor/BrowserExecUserscriptsParent.sys.mjs",
    },
    child: {
      esModuleURI:
        "chrome://userscripts/content/actor/BrowserExecUserscriptsChild.sys.mjs",
      events: { DOMContentLoaded: {} },
    },
    matches: ["<all_urls>"],
    allFrames: true,
  });
} catch (e) {
  console.error("browser-exec: failed to register userscript actor: " + e);
}

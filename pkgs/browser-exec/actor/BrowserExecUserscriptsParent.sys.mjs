// Parent side of the browser-exec userscript actor. Holds no per-window
// state of its own -- ScriptStore (a module-level singleton, not actor
// state) is the source of truth, per the platform docs' guidance that
// JSWindowActorChild state must not outlive its BrowsingContext, and here
// even the parent side is just a thin query interface.
import { ScriptStore } from "chrome://userscripts/content/actor/store.sys.mjs";

export class BrowserExecUserscriptParent extends JSWindowActorParent {
  async receiveMessage(msg) {
    if (msg.name === "BrowserExecUserscript:GetForUrl") {
      const scripts = await ScriptStore.forUrl(msg.data.url);
      // Only source + name/runAt cross the process boundary -- @match/
      // @description have already done their job.
      return scripts.map((s) => ({ name: s.name, runAt: s.runAt, source: s.source }));
    }
    return undefined;
  }
}

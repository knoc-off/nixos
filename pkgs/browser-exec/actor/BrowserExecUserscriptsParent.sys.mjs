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
      // Only source + name/runAt/grants cross the process boundary --
      // @match/@description have already done their job.
      return scripts.map((s) => ({ name: s.name, runAt: s.runAt, grants: s.grants, source: s.source }));
    }
    if (msg.name === "BrowserExecUserscript:Jev") {
      // Re-check the grant here rather than trusting the content process:
      // the script must match this document's URL and declare @grant jev.
      const url = this.manager.documentURI?.spec || "";
      const scripts = await ScriptStore.forUrl(url);
      const script = scripts.find((s) => s.name === msg.data.script && s.grants.includes("jev"));
      if (!script) throw new Error(`userscript ${JSON.stringify(msg.data.script)} has no @grant jev for ${url}`);
      const { USERSCRIPT_API } = ChromeUtils.importESModule("chrome://userscripts/content/jev.sys.mjs");
      const arity = { ask: 2, noul: 2, choose: 3, score: 3 }[msg.data.fn];
      if (!arity) throw new Error(`jev.${msg.data.fn} is not available to userscripts`);
      const args = JSON.parse(msg.data.args);
      // Positional args, then opts tagged with the script name for the log.
      const result = await USERSCRIPT_API[msg.data.fn](...args.slice(0, arity), {
        ...(args[arity] || {}),
        caller: script.name,
      });
      return JSON.stringify(result);
    }
    return undefined;
  }
}

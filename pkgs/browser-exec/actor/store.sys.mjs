// Shared state for the browser-exec userscript loader. Lives outside the
// actor pair (rather than as static state on BrowserExecUserscriptsParent)
// because it's also reached directly from the bridge sandbox's
// reloadUserscripts() helper, which has no actor/window context to hang off.
//
// Reload just re-runs load() -- there is no incremental diff. Profile-local
// script libraries are small (tens of files at most) and reload is a rare,
// explicit action (author saves a file, then calls it), so re-parsing
// everything is cheap and avoids a second, staler code path.
import { IOUtils } from "resource://gre/modules/IOUtils.sys.mjs";
import { parseUserscript, matchesAny } from "chrome://userscripts/content/match.mjs";

const DEFAULT_DIR_PREF = "browserexec.userscriptsDir";

function scriptsDir() {
  try {
    return Services.prefs.getStringPref(DEFAULT_DIR_PREF);
  } catch (_) {
    return Services.env.get("HOME") + "/.local/share/browser-exec/userscripts";
  }
}

export const ScriptStore = {
  _scripts: null,

  async load() {
    const dir = scriptsDir();
    const scripts = [];
    let children;
    try {
      children = await IOUtils.getChildren(dir);
    } catch (e) {
      // No library yet -- not an error, just nothing to inject.
      this._scripts = scripts;
      return scripts;
    }
    for (const path of children) {
      if (!path.endsWith(".user.js")) continue;
      try {
        const bytes = await IOUtils.read(path);
        const source = new TextDecoder().decode(bytes);
        const meta = parseUserscript(source);
        if (!meta.match.length) {
          console.warn(`browser-exec: ${path} has no @match, skipping`);
          continue;
        }
        scripts.push({ path, source, ...meta });
      } catch (e) {
        console.error(`browser-exec: failed to load ${path}: ${e}`);
      }
    }
    this._scripts = scripts;
    return scripts;
  },

  async ensureLoaded() {
    if (this._scripts === null) await this.load();
    return this._scripts;
  },

  async reload() {
    await this.load();
    return { count: this._scripts.length, scripts: this._scripts.map((s) => s.path) };
  },

  async forUrl(url) {
    const scripts = await this.ensureLoaded();
    return scripts.filter((s) => matchesAny(s.match, url));
  },
};

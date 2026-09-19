// Child side of the browser-exec userscript actor: on DOMContentLoaded, asks
// the parent for scripts matching this document's URL and evals each one
// directly into the page's own scope.
//
// wantXrays: false is what makes this behave like a real userscript rather
// than chrome-privileged code poking at content through Xray wrappers -- it
// matches Tampermonkey/Violentmonkey's own `@grant none` sandbox convention,
// where the script sees the page's own JS environment (its jQuery, its
// globals) rather than a security-wrapped view of it. There is no GM_* API
// surface: @grant none is the only mode (see pkgs/browser-exec's design
// doc -- GM_* is explicitly deferred until a script actually needs storage).
export class BrowserExecUserscriptChild extends JSWindowActorChild {
  handleEvent(event) {
    if (event.type !== "DOMContentLoaded") return;
    this.inject();
  }

  async inject() {
    const win = this.contentWindow;
    if (!win || !this.document || !this.document.location) return;
    const url = this.document.location.href;
    if (!/^https?:/.test(url)) return; // skip about:, chrome:, file:, etc.

    let scripts;
    try {
      scripts = await this.sendQuery("BrowserExecUserscript:GetForUrl", { url });
    } catch (e) {
      return; // actor torn down mid-flight (navigation) -- nothing to do
    }
    if (!scripts || !scripts.length) return;

    for (const script of scripts) {
      try {
        const sandbox = Cu.Sandbox(win, {
          sandboxPrototype: win,
          wantXrays: false,
          sandboxName: `browser-exec:${script.name || "userscript"}`,
        });
        Cu.evalInSandbox(script.source, sandbox, undefined, url);
      } catch (e) {
        console.error(`browser-exec: userscript '${script.name}' failed on ${url}: ${e}`);
      }
    }
  }
}

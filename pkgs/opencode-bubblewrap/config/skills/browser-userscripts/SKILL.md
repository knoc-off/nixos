---
name: browser-userscripts
description: Write or edit a persistent Tampermonkey-style userscript for firefox-neo (auto-runs on matching pages), as opposed to one-off browser_exec evals.
---

# firefox-neo userscripts

Userscripts are file-based and separate from `browser_exec` snippets:

1. Write a Tampermonkey-style `*.user.js` with a `==UserScript==` header
   (at least `@name` and `@match`) into
   `~/.local/share/browser-exec/userscripts/` using the normal Write/Edit tools.
2. Call `browser_exec` with `reload: true` so the bridge re-scans the library.

`browser_exec` never writes userscript files itself — it is eval and
orchestration, not the library. Iterate on the logic first with
`browser_exec` (`world: "page"`) against a matching tab, then save it as a
userscript once it works.

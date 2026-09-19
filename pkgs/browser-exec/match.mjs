// Pure functions for the browser-exec userscript loader: no Gecko globals, no
// node built-ins. Imported two ways that must stay byte-identical --
// chrome://userscripts/content/BrowserExecUserscripts/match.mjs from the
// actor, and a relative import from test.mjs under node:test. Any Gecko- or
// node-specific API here would break one of the two.

// Extracts @name/@description/@match(repeatable)/@run-at from a Tampermonkey-
// style "==UserScript==" metadata block. Unlike script-exec's JSON header,
// this format is the one userscript authors (and any model trained on
// Greasemonkey/Tampermonkey scripts) already know.
export function parseUserscript(source) {
  const m = source.match(/==UserScript==([\s\S]*?)==\/UserScript==/);
  const header = m ? m[1] : "";
  const grab = (tag) => header.match(new RegExp("^// @" + tag + "\\s+(.+)$", "m"))?.[1]?.trim() || "";
  const grabAll = (tag) =>
    Array.from(header.matchAll(new RegExp("^// @" + tag + "\\s+(.+)$", "gm"))).map((x) => x[1].trim());
  return {
    name: grab("name"),
    description: grab("description"),
    match: grabAll("match"),
    // document-idle is the only timing actually applied in v1 (see
    // BrowserExecUserscriptsChild.sys.mjs) -- the field is still captured now
    // so scripts written today don't need editing when @run-at is honored.
    runAt: grab("run-at") || "document-idle",
  };
}

// Browser-extension-style match pattern (or a plain glob) -> RegExp. Only `*`
// is a wildcard; everything else is escaped literally, matching what a
// userscript author already expects from "https://example.com/*".
export function globToRegExp(glob) {
  const escaped = glob.replace(/[.+^${}()|[\]\\?]/g, "\\$&").replace(/\*/g, ".*");
  return new RegExp("^" + escaped + "$");
}

export function matchesAny(patterns, url) {
  return patterns.some((p) => globToRegExp(p).test(url));
}

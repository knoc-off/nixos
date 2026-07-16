# Spell / typo checking via typos-lsp.
#
# typos-lsp wraps `typos`, a low-false-positive source-code spell checker. It
# checks the whole file -- comments, strings AND identifiers -- and surfaces
# misspellings (e.g. recieve -> receive) as LSP diagnostics with quick-fix code
# actions (reachable through the existing <leader>ca / tiny-code-action flow).
#
# The package (typos-lsp) is auto-injected by nixvim's server package map, so no
# extraPackages wiring is needed. It is independent of Vim's native `spell`
# option, so the two do not conflict.
#
# Escape hatch for false positives: drop a `typos.toml` / `_typos.toml` at the
# repo root (a documented root marker) to extend the dictionary per project.
{...}: {
  plugins.lsp.servers.typos_lsp.enable = true;
}

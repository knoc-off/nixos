# Spell / typo checking.
#
# Two independent checkers, deliberately:
#
# * typos-lsp -- wraps `typos`, a low-false-positive source-code spell checker.
#   It checks comments, strings AND identifiers, and surfaces misspellings
#   (e.g. recieve -> receive) as LSP diagnostics with quick-fix code actions
#   (reachable through the existing <leader>ca / tiny-code-action flow). It only
#   knows a fixed list of known typo pairs, so it never fires on jargon.
#   The package is auto-injected by nixvim's server package map, so no
#   extraPackages wiring is needed.
#
# * Neovim's native `spell` -- a real dictionary, for prose. This catches what
#   typos-lsp cannot: any word that simply is not a word.
#
# They do not conflict: typos-lsp reports diagnostics, `spell` draws its own
# highlight groups (SpellBad and friends, themed in `themes/default.nix`).
#
# `spelllang` is set in `settings/options.nix` (it is a plain option value);
# `spellfile` is set here because it needs a runtime `stdpath` lookup.
{ ... }:
{
  plugins.lsp.servers.typos_lsp.enable = true;

  autoCmd = [
    {
      # `spell` is window-local, so `FileType` alone would miss an already-open
      # buffer shown in a new window (`:b notes.md` in a fresh split).
      # `BufWinEnter` covers those, exactly as the old markdown conceal autocmd
      # had to.
      #
      # Enabling per-filetype rather than globally (`opts.spell = true`) is what
      # keeps the noise down. Treesitter's `@spell`/`@nospell` captures scope
      # spell to comments in any language whose parser is installed -- verified
      # on this config's neovim: a lua/nix/rust/python buffer flags `coment` in
      # a comment but leaves string contents and `identWithTeh` alone. Buffers
      # with *no* parser get no such scoping and flag every identifier, which is
      # why the deny-list below exists and why `buftype` is checked.
      event = [
        "FileType"
        "BufWinEnter"
      ];
      pattern = [ "*" ];
      callback.__raw = ''
        function(args)
          -- `spell` is window-local and sticky, so this has to decide both
          -- ways on every event: a window that once showed a markdown file
          -- keeps `spell` on for whatever buffer is loaded into it next, and
          -- `return`ing early would leave source code underlined.
          local function want(buf)
            -- Only real, editable files. Plugin UIs and scratch buffers
            -- (buftype "nofile", "terminal", "prompt", "quickfix", "help")
            -- have no parser and no business being spell checked -- a
            -- terminal full of underlined build output is unreadable.
            if vim.bo[buf].buftype ~= "" then
              return false
            end
            -- Filetypes with no treesitter parser whose content is mostly
            -- identifiers, paths or machine output. Without a parser there is
            -- no `@nospell` to scope anything, so every token gets flagged.
            local deny = {
              log = true,
              conf = true,
              csv = true,
              tsv = true,
              dosini = true,
              [""] = true,
            }
            return not deny[vim.bo[buf].filetype]
          end
          vim.wo.spell = want(args.buf)
        end
      '';
    }
    {
      # `zg` (add word) and `zw` (mark wrong) append to `spellfile`. Its default
      # is `stdpath("config")/spell/`, which under nixvim is a read-only nix
      # store path -- every `zg` would die with E484. Point it at writable
      # state instead.
      #
      # `spellfile` is *buffer*-local, so this sets the global default
      # (`vim.go`), which new buffers inherit -- `vim.opt` would only set it on
      # whatever buffer happened to be current at VimEnter.
      #
      # The directory has to exist first: Neovim does not create it, it just
      # fails to open the file with E484.
      event = [ "VimEnter" ];
      pattern = [ "*" ];
      callback.__raw = ''
        function()
          local dir = vim.fn.stdpath("data") .. "/spell"
          vim.fn.mkdir(dir, "p")
          vim.go.spellfile = dir .. "/en.utf-8.add"
        end
      '';
    }
  ];
}

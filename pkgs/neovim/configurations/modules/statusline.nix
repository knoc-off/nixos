# Statusline via mini.statusline
# Shows mode, file, git branch, diagnostics, LSP, cursor position, and a small
# "AI:N" count of items staged in the prompt-reference review (only when N > 0).
{lib, ...}: {
  plugins.mini = {
    enable = true;
    modules.statusline = {
      # Replicate mini.statusline's default active layout, but inject a compact
      # prompt-reference count next to the devinfo group. Kept minimal so it
      # never overlaps anything (it lives in the statusline, not a float).
      content.active = lib.nixvim.mkRaw ''
        function()
          local MiniStatusline = require('mini.statusline')
          local mode, mode_hl = MiniStatusline.section_mode({ trunc_width = 120 })
          local git         = MiniStatusline.section_git({ trunc_width = 40 })
          local diff        = MiniStatusline.section_diff({ trunc_width = 75 })
          local diagnostics = MiniStatusline.section_diagnostics({ trunc_width = 75 })
          local lsp         = MiniStatusline.section_lsp({ trunc_width = 75 })
          local filename    = MiniStatusline.section_filename({ trunc_width = 140 })
          local fileinfo    = MiniStatusline.section_fileinfo({ trunc_width = 120 })
          local location    = MiniStatusline.section_location({ trunc_width = 75 })
          local search      = MiniStatusline.section_searchcount({ trunc_width = 75 })

          -- prompt-reference staged count (empty string when nothing staged).
          local ai = ""
          local ok, pr = pcall(require, 'prompt-reference')
          if ok and pr.count then
            local n = pr.count()
            if n > 0 then ai = "AI:" .. n end
          end

          -- pick-scope indicator: hidden at repo root, "*" suffix when pinned
          -- (vs auto-detected from crate/package markers).
          local scope = ""
          if _G.PickScope then
            local label = _G.PickScope.label()
            if label then scope = "[" .. label .. (_G.PickScope.is_pinned() and "*" or "") .. "]" end
          end

          -- DAP session indicator: shown only while a debug session is live.
          local dbg = ""
          local ok_dap, dap = pcall(require, 'dap')
          if ok_dap and dap.session() ~= nil then
            local status = dap.status()
            dbg = "● DBG" .. (status ~= "" and (" " .. status) or "")
          end

          return MiniStatusline.combine_groups({
            { hl = mode_hl,                 strings = { mode } },
            { hl = 'MiniStatuslineDevinfo', strings = { git, diff, diagnostics, lsp, ai, scope, dbg } },
            '%<',
            { hl = 'MiniStatuslineFilename', strings = { filename } },
            '%=',
            { hl = 'MiniStatuslineFileinfo', strings = { fileinfo } },
            { hl = mode_hl,                  strings = { search, location } },
          })
        end
      '';
    };
  };
}

# ast-grep structural search - AST-aware search/replace that text/regex tools
# (and rust-analyzer) can't do. No Neovim plugin exists for it, so we drive the
# `ast-grep` (sg) CLI directly and stream results into a mini.pick list with
# preview + jump, matching the UX of the other pickers.
#
#   <leader>fa  prompt for a structural pattern (e.g. `let $A = $B`) and search
#               the project; language is inferred from the current filetype.
#
# Pattern syntax: https://ast-grep.github.io/guide/pattern-syntax.html
{lib, pkgs, ...}: {
  extraPackages = [pkgs.ast-grep];

  keymaps = [
    {
      mode = "n";
      key = "<leader>fa";
      action = lib.nixvim.mkRaw ''
        function()
          local MiniPick = require('mini.pick')

          -- Map Neovim filetypes to ast-grep language names where they differ.
          local ft_to_lang = {
            typescriptreact = "tsx",
            javascriptreact = "jsx",
            javascript = "js",
            typescript = "ts",
          }
          local ft = vim.bo.filetype
          local lang = ft_to_lang[ft] or ft
          if lang == "" then
            vim.notify("ast-grep: no filetype for current buffer", vim.log.levels.WARN)
            return
          end

          local pattern = vim.fn.input("ast-grep pattern (" .. lang .. "): ")
          if pattern == nil or pattern == "" then return end

          local cmd = {
            "ast-grep", "run",
            "--pattern", pattern,
            "--lang", lang,
            "--json=stream",
            (vim.fn.getcwd()),
          }

          local out = vim.fn.systemlist(cmd)
          if vim.v.shell_error ~= 0 and #out == 0 then
            vim.notify("ast-grep: no matches or error", vim.log.levels.INFO)
            return
          end

          local items = {}
          for _, line in ipairs(out) do
            local ok, obj = pcall(vim.json.decode, line)
            if ok and obj and obj.file then
              local lnum = (obj.range and obj.range.start.line or 0) + 1
              local col = (obj.range and obj.range.start.column or 0) + 1
              local text = (obj.lines or obj.text or ""):gsub("\n.*", "")
              items[#items + 1] = {
                text = string.format("%s:%d: %s", obj.file, lnum, text),
                path = obj.file,
                lnum = lnum,
                col = col,
              }
            end
          end

          if #items == 0 then
            vim.notify("ast-grep: no matches", vim.log.levels.INFO)
            return
          end

          MiniPick.start({
            source = {
              name = "ast-grep (" .. pattern .. ")",
              items = items,
              show = function(buf_id, items_arr, query)
                MiniPick.default_show(buf_id, items_arr, query, { show_icons = true })
              end,
              choose = function(item)
                if not item then return end
                vim.schedule(function()
                  vim.cmd("edit " .. vim.fn.fnameescape(item.path))
                  pcall(vim.api.nvim_win_set_cursor, 0, { item.lnum, item.col - 1 })
                end)
              end,
            },
          })
        end
      '';
      options = { silent = true; desc = "AST search (ast-grep)"; };
    }
  ];
}

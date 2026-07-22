# prompt-reference.nvim - stage code references (each with its own prompt) into
# a review, then copy the whole bundle formatted for pasting into an LLM.
# https://github.com/r10a/prompt-reference.nvim
#
# Built locally via buildVimPlugin (same pattern as tiny-code-action). The
# plugin's own default keymaps are NOT used (keymaps = false) because they
# collide with our setup: its visual <CR> clashes with treesitter
# incremental_selection, and its <Tab><Tab> clashes with blink snippet jumping.
# We bind our own under the free <leader>a ("AI review") namespace instead.
#
#   <leader>aa  (visual) add the selection to the review (prompts for text)
#   <leader>ap  (normal) peek the review in mini.pick (search + <Tab> preview,
#               <CR> jumps to the captured source)
#   <leader>ac  (normal) copy the review to the clipboard and clear it
#
# The plugin's own persistent bottom-right panel is patched out (see postPatch);
# visibility is entirely via this peek picker + the notify on add + a small
# "AI:N" count in the statusline (see statusline.nix).
{pkgs, lib, ...}: {
  whichKeyGroups = [{__unkeyed = "<leader>a"; group = "AI review";}];

  extraPlugins = [
    (pkgs.vimUtils.buildVimPlugin {
      pname = "prompt-reference-nvim";
      version = "unstable-2025-06-01";
      src = pkgs.fetchFromGitHub {
        owner = "r10a";
        repo = "prompt-reference.nvim";
        rev = "dff576e84ca850431f66c10f28834a830990b6e8";
        hash = "sha256-p9QG2Tqv3ySadsv3+TMLOohp5QAeql+LuATIzwN3Lkc=";
      };
      # NOTE: ugly, fragile, intentional patches. Upstream has no public API for
      # the staged review data and force-shows a persistent bottom-right float
      # that overlaps our statusline. Rather than fight it at runtime, we patch
      # the source so (a) the staged list is queryable and (b) the auto-panel is
      # gone — then we drive the whole UX through mini.pick + the statusline.
      # Every substitution uses --replace-fail, so if upstream changes these
      # exact strings the BUILD FAILS LOUDLY (by design). If that happens after
      # bumping `rev`, re-read lua/prompt-reference/init.lua and re-derive these.
      postPatch = ''
        # 1. Expose staged data so mini.pick can index it and the statusline can
        #    show a count. Copies are returned so the picker can't mutate state.
        substituteInPlace lua/prompt-reference/init.lua \
          --replace-fail 'function M.setup(opts)' \
        'function M.count() return #staged end

function M.items() return vim.deepcopy(staged) end

function M.format_item(ctx) return format_ctx(ctx) end

function M.setup(opts)'

        # 2. Kill the persistent bottom-right panel: neutralise refresh_panel so
        #    it never opens a float. review()/add_selection()/copy_all() still
        #    work; they just no longer pop the overlapping window.
        substituteInPlace lua/prompt-reference/init.lua \
          --replace-fail 'local function refresh_panel()' \
                         'local function refresh_panel() do return end'
      '';
      meta = {
        description = "Stage code references with prompts into a review, copy for an LLM";
        homepage = "https://github.com/r10a/prompt-reference.nvim";
      };
    })
  ];

  extraConfigLua = ''
    require("prompt-reference").setup({
      output_style = "xml", -- xml parses more reliably for Claude
      keymaps = false, -- bind our own below to avoid collisions
    })
  '';

  keymaps = [
    {
      mode = "x";
      key = "<leader>aa";
      action = lib.nixvim.mkRaw "function() require('prompt-reference').add_selection() end";
      options = { silent = true; desc = "Add selection to review"; };
    }
    {
      mode = "n";
      key = "<leader>ap";
      action = lib.nixvim.mkRaw ''
        function()
          local pr = require('prompt-reference')
          local staged = pr.items()
          if #staged == 0 then
            vim.notify("prompt-reference: nothing staged", vim.log.levels.INFO)
            return
          end
          -- Build searchable items; keep the original ctx for preview/jump.
          local items = {}
          for i, ctx in ipairs(staged) do
            local snippet = (ctx.prompt or ""):gsub("%s+", " "):sub(1, 50)
            local text = string.format("%d. %s:%s", i, ctx.path, ctx.range)
            if snippet ~= "" then text = text .. "  — " .. snippet end
            -- lnum = first line of the captured range, for <CR> jump-to-source.
            local lnum = tonumber((ctx.range or "1"):match("^(%d+)")) or 1
            items[i] = { text = text, ctx = ctx, path = ctx.path, lnum = lnum }
          end
          local preview = function(buf_id, item)
            local rendered = pr.format_item(item.ctx)
            vim.api.nvim_buf_set_lines(buf_id, 0, -1, false, vim.split(rendered, "\n"))
            -- Highlight the previewed body with the item's own filetype.
            local ft = item.ctx.filetype
            if ft and ft ~= "" and not pcall(vim.treesitter.start, buf_id, ft) then
              vim.bo[buf_id].syntax = ft
            end
          end
          require('mini.pick').start({
            source = { items = items, name = 'AI review (' .. #staged .. ')', preview = preview },
          })
        end
      '';
      options = { silent = true; desc = "Peek review (mini.pick)"; };
    }
    {
      mode = "n";
      key = "<leader>ac";
      action = lib.nixvim.mkRaw "function() require('prompt-reference').copy_all() end";
      options = { silent = true; desc = "Copy review"; };
    }
  ];
}

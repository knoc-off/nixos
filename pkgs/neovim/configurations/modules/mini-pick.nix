# Fuzzy finder via mini.pick + mini.extra (replaces telescope)
# Also routes vim.ui.select (code actions, rust target, session pickers) through
# mini.pick for a consistent picker UX across the whole config.
{lib, pkgs, ...}: {
  # Guarantee the CLI tools mini.pick shells out to are always present,
  # independent of the ambient system PATH. mini.pick prefers rg > fd > git.
  extraPackages = [pkgs.ripgrep pkgs.fd];

  plugins.mini.modules = {
    pick = {
      # Match the telescope muscle memory: Ctrl-j/k to move the selection.
      mappings = {
        move_down = "<C-j>";
        move_up = "<C-k>";
      };
    };
    # Registers the extended pickers (oldfiles, diagnostic, lsp, ...) into
    # MiniPick.registry, also exposing them as `:Pick <name>` for discovery.
    extra = {};
  };

  extraConfigLua = ''
    -- Route vim.ui.select through mini.pick (code actions, session pickers, etc.)
    vim.ui.select = require('mini.pick').ui_select
  '';

  keymaps = let
    mk = key: fn: desc: {
      mode = "n";
      inherit key;
      action = lib.nixvim.mkRaw "function() ${fn} end";
      options = {
        silent = true;
        inherit desc;
      };
    };
  in [
    (mk "<leader>ff" "require('mini.pick').builtin.files()" "Find files")
    (mk "<leader>fg" "require('mini.pick').builtin.grep_live()" "Live grep")
    (mk "<C-f>" "require('mini.pick').builtin.grep_live()" "Live grep")
    (mk "<leader>fh" "require('mini.pick').builtin.help()" "Help tags")
    (mk "<leader>fr" "require('mini.pick').builtin.resume()" "Resume last picker")
    (mk "<C-p>" "require('mini.extra').pickers.git_files()" "Git files")
    (mk "<leader>fo" "require('mini.extra').pickers.oldfiles()" "Recent files")
    (mk "<leader>fd" "require('mini.extra').pickers.diagnostic()" "Diagnostics")
    (mk "<leader>f/" "require('mini.extra').pickers.buf_lines({ scope = 'current' })" "Search in buffer")
    (mk "<leader>fc" "require('mini.extra').pickers.commands()" "Commands")
    (mk "<leader>fk" "require('mini.extra').pickers.keymaps()" "Keymaps")
    (mk "<leader>ls" "require('mini.extra').pickers.lsp({ scope = 'document_symbol' })" "Document symbols")
    (mk "<leader>lS" "require('mini.extra').pickers.lsp({ scope = 'workspace_symbol' })" "Workspace symbols")

    # Buffers picker with <C-d> to wipeout the buffer under the cursor.
    {
      mode = "n";
      key = "<leader>fb";
      action = lib.nixvim.mkRaw ''
        function()
          local MiniPick = require('mini.pick')
          MiniPick.builtin.buffers({}, {
            mappings = {
              wipeout = {
                char = "<C-d>",
                func = function()
                  local cur = MiniPick.get_picker_matches().current
                  if cur then
                    vim.api.nvim_buf_delete(cur.bufnr, {})
                  end
                end,
              },
            },
          })
        end
      '';
      options = {
        silent = true;
        desc = "Buffers";
      };
    }
  ];
}

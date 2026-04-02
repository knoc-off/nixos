# Buffer management with bufferline
# Provides visual buffer tabs and navigation keybindings
{lib, ...}: let
  # Generate <leader>N keymaps for buffer 1-9
  goToBufferKeymaps = builtins.genList (i: {
    mode = "n";
    key = "<leader>${toString (i + 1)}";
    action = "<cmd>BufferLineGoToBuffer ${toString (i + 1)}<cr>";
    options = {
      silent = true;
      desc = "Go to buffer ${toString (i + 1)}";
    };
  }) 9;
in {
  plugins.bufferline = {
    enable = true;
    settings.options = {
      mode = "buffers";
      numbers = "none";
      close_command = "bdelete! %d";
      right_mouse_command = "bdelete! %d";
      left_mouse_command = "buffer %d";

      truncate_names = true;
      tab_size = 18;
      max_name_length = 18;
      separator_style = "slope";
      show_buffer_close_icons = true;
      show_close_icon = false;
      show_tab_indicators = true;
      show_duplicate_prefix = true;
      enforce_regular_tabs = false;

      diagnostics = "nvim_lsp";
      diagnostics_update_in_insert = false;
      diagnostics_indicator = lib.nixvim.mkRaw ''
        function(count, level)
          local icon = level:match("error") and " " or " "
          return " " .. icon .. count
        end
      '';

      sort_by = "insert_after_current";
    };
  };

  keymaps =
    [
      {
        mode = "n";
        key = "<Tab>";
        action = "<cmd>BufferLineCycleNext<cr>";
        options = { silent = true; desc = "Next buffer"; };
      }
      {
        mode = "n";
        key = "<S-Tab>";
        action = "<cmd>BufferLineCyclePrev<cr>";
        options = { silent = true; desc = "Previous buffer"; };
      }
      {
        mode = "n";
        key = "<leader>bp";
        action = "<cmd>BufferLinePick<cr>";
        options = { silent = true; desc = "Pick buffer"; };
      }
      {
        mode = "n";
        key = "<leader>bc";
        action = "<cmd>BufferLinePickClose<cr>";
        options = { silent = true; desc = "Pick buffer to close"; };
      }
      {
        mode = "n";
        key = "<leader>bD";
        action = "<cmd>BufferLineCloseOthers<cr>";
        options = { silent = true; desc = "Close other buffers"; };
      }
      {
        mode = "n";
        key = "<leader>bh";
        action = "<cmd>BufferLineCloseLeft<cr>";
        options = { silent = true; desc = "Close buffers to the left"; };
      }
      {
        mode = "n";
        key = "<leader>bl";
        action = "<cmd>BufferLineCloseRight<cr>";
        options = { silent = true; desc = "Close buffers to the right"; };
      }
      {
        mode = "n";
        key = "<leader>b>";
        action = "<cmd>BufferLineMoveNext<cr>";
        options = { silent = true; desc = "Move buffer right"; };
      }
      {
        mode = "n";
        key = "<leader>b<";
        action = "<cmd>BufferLineMovePrev<cr>";
        options = { silent = true; desc = "Move buffer left"; };
      }
      {
        mode = "n";
        key = "<leader>x";
        action = lib.nixvim.mkRaw ''
          function()
            local bufnr = vim.api.nvim_get_current_buf()
            vim.cmd('BufferLineCyclePrev')
            vim.cmd('bdelete! ' .. bufnr)
          end
        '';
        options = { silent = true; desc = "Close current buffer"; };
      }
    ]
    ++ goToBufferKeymaps;
}

# Buffer management with bufferline
# Provides visual buffer tabs and navigation keybindings
{lib, ...}: {
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

      offsets = [
        {
          filetype = "neo-tree";
          text = "Files";
          text_align = "center";
          separator = true;
        }
        {
          filetype = "NvimTree";
          text = "Files";
          text_align = "center";
          separator = true;
        }
      ];
    };
  };

  keymaps = [
    {
      mode = "n";
      key = "<Tab>";
      action = "<cmd>BufferLineCycleNext<cr>";
      options = {
        silent = true;
        desc = "Next buffer";
      };
    }
    {
      mode = "n";
      key = "<S-Tab>";
      action = "<cmd>BufferLineCyclePrev<cr>";
      options = {
        silent = true;
        desc = "Previous buffer";
      };
    }

    {
      mode = "n";
      key = "<leader>bp";
      action = "<cmd>BufferLinePick<cr>";
      options = {
        silent = true;
        desc = "Pick buffer";
      };
    }
    {
      mode = "n";
      key = "<leader>bc";
      action = "<cmd>BufferLinePickClose<cr>";
      options = {
        silent = true;
        desc = "Pick buffer to close";
      };
    }
    {
      mode = "n";
      key = "<leader>bD";
      action = "<cmd>BufferLineCloseOthers<cr>";
      options = {
        silent = true;
        desc = "Close other buffers";
      };
    }
    {
      mode = "n";
      key = "<leader>bh";
      action = "<cmd>BufferLineCloseLeft<cr>";
      options = {
        silent = true;
        desc = "Close buffers to the left";
      };
    }
    {
      mode = "n";
      key = "<leader>bl";
      action = "<cmd>BufferLineCloseRight<cr>";
      options = {
        silent = true;
        desc = "Close buffers to the right";
      };
    }

    {
      mode = "n";
      key = "<leader>b>";
      action = "<cmd>BufferLineMoveNext<cr>";
      options = {
        silent = true;
        desc = "Move buffer right";
      };
    }
    {
      mode = "n";
      key = "<leader>b<";
      action = "<cmd>BufferLineMovePrev<cr>";
      options = {
        silent = true;
        desc = "Move buffer left";
      };
    }

    {
      mode = "n";
      key = "<leader>x";
      action = lib.nixvim.mkRaw ''
        function()
          local bufnr = vim.api.nvim_get_current_buf()
          -- Switch to previous buffer first, then delete
          vim.cmd('BufferLineCyclePrev')
          vim.cmd('bdelete! ' .. bufnr)
        end
      '';
      options = {
        silent = true;
        desc = "Close current buffer";
      };
    }

    {
      mode = "n";
      key = "<leader>1";
      action = "<cmd>BufferLineGoToBuffer 1<cr>";
      options = {silent = true; desc = "Go to buffer 1";};
    }
    {
      mode = "n";
      key = "<leader>2";
      action = "<cmd>BufferLineGoToBuffer 2<cr>";
      options = {silent = true; desc = "Go to buffer 2";};
    }
    {
      mode = "n";
      key = "<leader>3";
      action = "<cmd>BufferLineGoToBuffer 3<cr>";
      options = {silent = true; desc = "Go to buffer 3";};
    }
    {
      mode = "n";
      key = "<leader>4";
      action = "<cmd>BufferLineGoToBuffer 4<cr>";
      options = {silent = true; desc = "Go to buffer 4";};
    }
    {
      mode = "n";
      key = "<leader>5";
      action = "<cmd>BufferLineGoToBuffer 5<cr>";
      options = {silent = true; desc = "Go to buffer 5";};
    }
    {
      mode = "n";
      key = "<leader>6";
      action = "<cmd>BufferLineGoToBuffer 6<cr>";
      options = {silent = true; desc = "Go to buffer 6";};
    }
    {
      mode = "n";
      key = "<leader>7";
      action = "<cmd>BufferLineGoToBuffer 7<cr>";
      options = {silent = true; desc = "Go to buffer 7";};
    }
    {
      mode = "n";
      key = "<leader>8";
      action = "<cmd>BufferLineGoToBuffer 8<cr>";
      options = {silent = true; desc = "Go to buffer 8";};
    }
    {
      mode = "n";
      key = "<leader>9";
      action = "<cmd>BufferLineGoToBuffer 9<cr>";
      options = {silent = true; desc = "Go to buffer 9";};
    }
  ];
}

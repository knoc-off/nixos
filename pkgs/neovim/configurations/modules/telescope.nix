# Telescope fuzzy finder
# - fzf-native for fast sorting
# - ui-select for code actions and vim.ui.select
{lib, ...}: {
  plugins.telescope = {
    enable = true;

    extensions = {
      fzf-native = {
        enable = true;
        settings = {
          fuzzy = true;
          override_generic_sorter = true;
          override_file_sorter = true;
          case_mode = "smart_case";
        };
      };

      ui-select = {
        enable = true;
        settings = {
          __unkeyed = lib.nixvim.mkRaw "require('telescope.themes').get_dropdown()";
        };
      };

      undo.enable = true;
    };

    settings = {
      defaults = {
        prompt_prefix = "   ";
        selection_caret = "  ";
        entry_prefix = "  ";

        sorting_strategy = "ascending";
        layout_strategy = "horizontal";
        layout_config = {
          horizontal = {
            prompt_position = "top";
            preview_width = 0.5;
          };
          width = 0.9;
          height = 0.85;
        };

        file_ignore_patterns = [
          "^.git/"
          "^.mypy_cache/"
          "^__pycache__/"
          "^node_modules/"
          "^target/"
          "^.direnv/"
          "%.lock"
        ];

        path_display = ["truncate"];
        set_env.COLORTERM = "truecolor";

        mappings = {
          i = {
            "<C-j>" = lib.nixvim.mkRaw "require('telescope.actions').move_selection_next";
            "<C-k>" = lib.nixvim.mkRaw "require('telescope.actions').move_selection_previous";
            "<C-q>" = lib.nixvim.mkRaw "require('telescope.actions').send_selected_to_qflist + require('telescope.actions').open_qflist";
            "<Esc>" = lib.nixvim.mkRaw "require('telescope.actions').close";
          };
          n = {
            q = lib.nixvim.mkRaw "require('telescope.actions').close";
          };
        };
      };

      pickers = {
        find_files = {
          hidden = true;
          follow = true;
        };
        live_grep = {
          additional_args = lib.nixvim.mkRaw ''function() return { "--hidden" } end'';
        };
        buffers = {
          show_all_buffers = true;
          sort_lastused = true;
          mappings = {
            i = {
              "<C-d>" = lib.nixvim.mkRaw "require('telescope.actions').delete_buffer";
            };
            n = {
              d = lib.nixvim.mkRaw "require('telescope.actions').delete_buffer";
            };
          };
        };
      };
    };

    keymaps = {
      "<leader>ff" = {
        action = "find_files";
        options.desc = "Find files";
      };
      "<leader>fg" = {
        action = "live_grep";
        options.desc = "Live grep";
      };
      "<leader>fb" = {
        action = "buffers";
        options.desc = "Buffers";
      };
      "<leader>fh" = {
        action = "help_tags";
        options.desc = "Help tags";
      };
      "<leader>fo" = {
        action = "oldfiles";
        options.desc = "Recent files";
      };
      "<leader>fd" = {
        action = "diagnostics";
        options.desc = "Diagnostics";
      };
      "<leader>fu" = {
        action = "undo";
        options.desc = "Undo history";
      };

      "<C-p>" = {
        action = "git_files";
        options.desc = "Git files";
      };
      "<C-f>" = {
        action = "live_grep";
        options.desc = "Grep";
      };

      "<leader>f/" = {
        action = "current_buffer_fuzzy_find";
        options.desc = "Search in buffer";
      };
      "<leader>fc" = {
        action = "commands";
        options.desc = "Commands";
      };
      "<leader>fk" = {
        action = "keymaps";
        options.desc = "Keymaps";
      };
      "<leader>fr" = {
        action = "resume";
        options.desc = "Resume last search";
      };

      # LSP pickers (supplement to gd, gr, etc.)
      "<leader>ls" = {
        action = "lsp_document_symbols";
        options.desc = "Document symbols";
      };
      "<leader>lS" = {
        action = "lsp_workspace_symbols";
        options.desc = "Workspace symbols";
      };
    };
  };
}

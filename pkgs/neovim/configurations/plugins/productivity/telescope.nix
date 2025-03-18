{ helpers, lib, ... }: {
  plugins.telescope = {
    enable = true;

    extensions.undo.enable = true;

    keymaps = {
      # Find files using Telescope command-line sugar.
      "<leader>ff" = "find_files";
      "<leader>fg" = "live_grep";
      "<leader>b" = "buffers";
      "<leader>fh" = "help_tags";
      "<leader>fd" = "diagnostics";
      "<leader>fu" = "undo"; # Added undo keymap

      # FZF like bindings
      "<C-p>" = "git_files";
      "<leader>p" = "oldfiles";
      "<C-f>" = "live_grep";
    };

    settings.defaults = {
      file_ignore_patterns = [
        "^.git/"
        "^.mypy_cache/"
        "^__pycache__/"
        "^output/"
        "^data/"
        "%.ipynb"
      ];
      set_env.COLORTERM = "truecolor";
    };

    extensions.undo = {
      settings = {
        use_delta = true;
        side_by_side = true;
        entry_format = "state #$ID, $STAT, $TIME";
        time_format = "%Y-%m-%d %H:%M:%S";
        mappings = {
          i = {
            "<cr>" = "require('telescope-undo.actions').yank_additions";
            "<s-cr>" = "require('telescope-undo.actions').yank_deletions";
            "<c-cr>" = "require('telescope-undo.actions').restore";
          };
          n = {
            "y" = "require('telescope-undo.actions').yank_additions";
            "Y" = "require('telescope-undo.actions').yank_deletions";
            "u" = "require('telescope-undo.actions').restore";
          };
        };
      };
    };
  };

  plugins.which-key.settings.spec = [
    { "<leader>f" = { name = "Telescope"; }; }
    { "<leader>ff" = { name = "Search Find files"; }; }
    { "<leader>fF" = { name = "Find files Hidden Also"; }; }
    { "<leader>fr" = { name = "Search Recent files"; }; }
    { "<leader>fk" = { name = "Search Keymaps"; }; }
    { "<leader>fs" = { name = "Search Telescope"; }; }
    { "<leader>fg" = { name = "Search Live Grep"; }; }
    { "<leader>fu" = { name = "Undo History"; }; }
  ];

}

{ helpers, lib, ... }: {
  plugins.telescope = {
    enable = true;

    keymaps = {
      # Find files using Telescope command-line sugar.
      "<leader>ff" = "find_files";
      "<leader>fg" = "live_grep";
      "<leader>b" = "buffers";
      "<leader>fh" = "help_tags";
      "<leader>fd" = "diagnostics";

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
  };
  plugins.which-key = {
    enable = true;
    registrations = {
      "<leader>s" = "Search";
      "<leader>sf" = "Search Find files";
      "<leader>sF" = "Find files Hidden Also";
      "<leader>sr" = "Search Recent files";
      "<leader>sk" = "Search Keymaps";
      "<leader>ss" = "Search Telescope";
      "<leader>sg" = "Search Live Grep";
    };
  };
}

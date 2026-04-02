# Treesitter syntax highlighting and context
{lib, ...}: {
  plugins.treesitter = {
    enable = true;
    settings = {
      highlight.enable = true;
      indent.enable = true;
    };
  };

  # FIXME: remove after nvim-treesitter Nix indent queries are fixed upstream
  # Treesitter indent over-indents inside list_expression nodes in Nix.
  # Falls back to autoindent (copy previous line). Alejandra fixes on save.
  autoCmd = [
    {
      event = "FileType";
      pattern = ["nix"];
      callback.__raw = ''
        function()
          vim.bo.indentexpr = ""
        end
      '';
    }
  ];

  plugins.treesitter-context = {
    enable = true;
    settings = {
      max_lines = 0;
      min_window_height = 0;
      line_numbers = true;
      multiline_threshold = 20;
      trim_scope = "outer";
      mode = "cursor";
      zindex = 20;
    };
  };
}

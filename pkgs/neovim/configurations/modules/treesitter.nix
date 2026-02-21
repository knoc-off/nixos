{...}: {
  plugins.treesitter = {
    enable = true;
    settings.highlight.enable = true;
  };

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

  plugins.mini.modules.notify = {};
}

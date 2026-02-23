{lib, ...}: {
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
  plugins.mini.modules.animate = {
    cursor.enable = false;
    resize.enable = false;
    open.enable = false;
    close.enable = false;
    scroll = {
      enable = true;
      timing.__raw = ''require("mini.animate").gen_timing.linear({ duration = 50, unit = "total" })'';
      subscroll.__raw = ''require("mini.animate").gen_subscroll.equal({ max_output_steps = 30 })'';
    };
  };

  # Disable scroll animation in large files
  autoCmd = [{
    event = "BufEnter";
    callback.__raw = ''
      function()
        vim.b.minianimate_disable = vim.api.nvim_buf_line_count(0) > 5000
      end
    '';
  }];
}

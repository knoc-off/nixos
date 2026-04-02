# UI polish: notifications, smooth scroll, icons
{lib, ...}: {
  plugins.mini = {
    enable = true;
    mockDevIcons = true;
    modules = {
      icons = {};
      notify = {};
      animate = {
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
    };
  };

  # Disable scroll animation in large files
  autoCmd = [
    {
      event = "BufEnter";
      callback.__raw = ''
        function()
          vim.b.minianimate_disable = vim.api.nvim_buf_line_count(0) > 5000
        end
      '';
    }
  ];
}

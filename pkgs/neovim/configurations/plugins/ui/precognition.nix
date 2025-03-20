{ pkgs, ... }: {
  # Add precognition-nvim to extraPlugins
  extraPlugins = with pkgs.vimExtraPlugins; [ precognition-nvim ];

  # Configure precognition-nvim
  extraConfigLua = ''
    require('precognition').setup({
      -- Add your configuration options here
      -- For example:
      startVisible = false,
      delay = 100,  -- delay in milliseconds
      ignored_filetypes = {},  -- filetypes to ignore
    })
  '';

  # Optional: Add keymappings for precognition-nvim
  keymaps = [
    {
      mode = "n";
      key = "<leader>pt";
      action = ":Precognition toggle<CR>";
      options = {
        silent = true;
        desc = "Toggle Precognition";
      };
    }
    {
      mode = "n";
      key = "<leader>pp";
      action = ":Precognition peek<CR>";
      options = {
        silent = true;
        desc = "Disable Precognition";
      };
    }
  ];

}

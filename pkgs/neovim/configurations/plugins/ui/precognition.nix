{ pkgs, ... }: {
  # Add precognition-nvim to extraPlugins
  extraPlugins = with pkgs.vimExtraPlugins; [ precognition-nvim ];

  # Configure precognition-nvim
  extraConfigLua = ''
    require('precognition').setup({
      -- Add your configuration options here
      -- For example:
      delay = 100,  -- delay in milliseconds
      ignored_filetypes = {},  -- filetypes to ignore
    })
  '';

  # Optional: Add keymappings for precognition-nvim
  keymaps = [
    {
      mode = "n";
      key = "<leader>pe";
      action = ":PrecognitionEnable<CR>";
      options = {
        silent = true;
        desc = "Enable Precognition";
      };
    }
    {
      mode = "n";
      key = "<leader>pd";
      action = ":PrecognitionDisable<CR>";
      options = {
        silent = true;
        desc = "Disable Precognition";
      };
    }
  ];

  # Optional: Add which-key registrations
  plugins.which-key.registrations = {
    "<leader>p" = "Precognition";
    "<leader>pe" = "Enable Precognition";
    "<leader>pd" = "Disable Precognition";
  };
}

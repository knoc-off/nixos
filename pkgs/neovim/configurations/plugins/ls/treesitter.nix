{ pkgs, ... }:
{
  plugins = {
    treesitter = {
      enable = true;
      nixvimInjections = true;
      # Optionally set auto_install and other global options
      settings = {
        auto_install = false;
        ensure_installed = [
          "bash"
          "c"
          "cpp"
          "css"
          "html"
          "javascript"
          "json"
          "lua"
          "nix"
          "python"
          "rust"
          "typescript"
          "vim"
          "yaml"
        ];
        incremental_selection = { enable = true; };
        indent = { enable = true; };
        highlight = { enable = true; };

        # Configure the textsubjects integration (provided by the extra plugin)
        textsubjects = {
          enable = true;
          prev_selection = ",";
          keymaps = {
            "<leader>." = "textsubjects-smart";
            "<leader>;" = "textsubjects-container-outer";
            "<leader>i;" = "textsubjects-container-inner";
          };
        };
      };
      # You can also override the default lua configuration if you need
      # to combine configuration steps. The module will build a Lua config
      # by calling:
      #   require('nvim-treesitter.configs').setup( settings )
      # so adding textsubjects inside settings ensures it is applied.
    };

    treesitter-textobjects = {
      enable = true;
    };

    indent-blankline = {
      enable = true;
      settings = {
        exclude = {
          filetypes = [
            "dashboard"
            "lspinfo"
            "packer"
            "checkhealth"
            "help"
            "man"
            "gitcommit"
            "TelescopePrompt"
            "TelescopeResults"
            "''"
          ];
        };
        indent = { char = "┊"; };
      };
    };
  };

  # Install the extra plugin that provides textsubjects queries.
  # This ensures that the query files (e.g. for textsubjects) are added to
  # the runtime path.
  extraPlugins = with pkgs.vimPlugins; [ nvim-treesitter-textsubjects ];
}


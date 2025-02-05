{pkgs, ...}: {
  plugins = {
    treesitter = {
      enable = true;
      nixvimInjections = true;
      settings = {
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
        incremental_selection = {
          enable = true;
        };
        indent = {
          enable = true;
        };
        highlight = {
          enable = true;
        };
      };
    };
    treesitter-textobjects = {enable = true;};
    mini.enable = false;
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
        indent = {char = "│";};
      };
    };
  };

  extraPlugins = with pkgs.vimPlugins; [nvim-treesitter-textsubjects];
  extraConfigLua = ''
    -- require('mini.indentscope').setup({
    --   symbol = "│",
    --   draw = {
    --     animation = require('mini.indentscope').gen_animation.none(),
    --   },
    -- })

    -- require("nvim-treesitter.configs").setup({
    --   textsubjects = {
    --     enable = true,
    --     prev_selection = ",", -- (Optional) keymap to select the previous selection
    --     keymaps = {
    --       ["."] = "textsubjects-smart",
    --       [";"] = "textsubjects-container-outer",
    --       ["i;"] = { "textsubjects-container-inner", desc = "Select inside containers (classes, functions, etc.)" },
    --     },
    --   },
    -- })
  '';
}

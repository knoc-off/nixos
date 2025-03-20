{ pkgs, ... }: {
  plugins = {
    web-devicons.enable = true;
    lsp = {
      enable = true;
      #  diagnostics = {
      #    update_in_insert = false;
      #  };
      servers = {
        bashls.enable = true;
        clangd.enable = true;
        cssls.enable = true;
        html.enable = true;
        jsonls.enable = true;
        pylsp.enable = true;
        rust_analyzer = {
          enable = true;
          installCargo = false;
          installRustc = false;
          #installCargo = true;
          #installRustc = true;
        };
        tailwindcss.enable = true;
      };
      keymaps = {
        silent = true;
        diagnostic = {
          "<leader>j" = "goto_next";
          "<leader>k" = "goto_prev";
        };
        lspBuf = {
          K = "hover";
          gD = "references";
          gd = "definition";
          gi = "implementation";
          gt = "type_definition";
          "<leader>ca" = "code_action";
          "<leader>a" = "code_action";
          "<leader>rn" = "rename";
        };
      };
    };

    lsp-format.enable = false;

    none-ls = {
      enable = true;
      sources = {
        formatting = {
          black.enable = true;
          prettier = {
            enable = true;
            #settings.extra_filetypes = [ "javascript" "javascriptreact" "typescript" "typescriptreact" "json" "css" "scss" "less" "html" "htmldjango" ];
          };
          djhtml.enable = true;
          nixfmt.enable = true;
        };
      };
    };
  };

  plugins.which-key.settings.spec = [
    { "<leader>l" = { name = "LSP"; }; }
    { "<leader>lf" = { name = "Format file"; }; }
    { "<leader>li" = { name = "LspInfo"; }; }
    { "<leader>lo" = { name = "Outline"; }; }
    { "<leader>lw" = { name = "Workspace Diagnostics"; }; }
    { "<leader>ld" = { name = "Line Diagnostics"; }; }
    { "<leader>la" = { name = "Code Action"; }; }
    { "<leader>a" = { name = "Quick Code Action"; }; }
    { "<leader>ll" = { name = "Toggle Ghost Text"; }; }
  ];


}

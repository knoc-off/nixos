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
          installCargo = true;
          installRustc = true;
        };
        ts_ls.enable = true;
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
            disableTsServerFormatter = true;
          };
          nixfmt.enable = true;
        };
      };
    };
  };

  plugins.which-key.registrations = {
    "<leader>l" = "LSP";
    "<leader>lf" = "Format file";
    "<leader>li" = "LspInfo";
    "<leader>lo" = "Outline";
    "<leader>lw" = "Workspace Diagnostics";
    "<leader>ld" = "Line Diagnostics";
    "<leader>la" = "Code Action";
    "<leader>ll" = "Toggle Ghost Text";
  };
}

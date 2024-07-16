{pkgs, ...}: {
  plugins = {
    lsp = {
      enable = true;
      servers = {
        bashls.enable = true;
        clangd.enable = true;
        cssls.enable = true;
        html.enable = true;
        jsonls.enable = true;
        pylsp.enable = true;
        rust-analyzer = {
          enable = true;
          installCargo = true;
          installRustc = true;
        };
        tsserver.enable = true;
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

    lsp-format.enable = true;

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
}

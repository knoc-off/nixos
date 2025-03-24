{ ... }: {
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

        # Python language servers
        pyright = {
          enable = true;
          settings = {
            python = {
              analysis = {
                typeCheckingMode = "basic";
                diagnosticMode = "workspace";
                inlayHints = {
                  functionReturnTypes = true;
                  variableTypes = true;
                };
              };
            };
          };
        };

        pylsp = {
          enable = true;
          settings = {
            plugins = {
              pycodestyle = {
                enabled = true;
                maxLineLength = 100;
              };
              pyflakes = { enabled = true; };
              pylint = { enabled = true; };
              yapf = { enabled = true; };
              rope_completion = { enabled = true; };
              mypy = { enabled = true; };
            };
          };
        };

        rust_analyzer = {
          enable = true;
          installCargo = false;
          installRustc = false;
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

  };

}

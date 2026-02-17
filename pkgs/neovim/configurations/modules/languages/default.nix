# Shared LSP infrastructure, common keymaps, and formatting base
# Import this alongside specific language modules (rust.nix, nix.nix, etc.)
{lib, pkgs, ...}: {
  plugins.fidget = {
    enable = true;
    settings = {
      progress = {
        display = {
          render_limit = 5;
          done_ttl = 2;
        };
      };
      notification = {
        window = {
          winblend = 0;
          border = "none";
        };
      };
    };
  };

  plugins.lsp = {
    enable = true;
    inlayHints = true;

    keymaps = {
      silent = true;

      diagnostic = {
        "<leader>j" = "goto_next";
        "<leader>k" = "goto_prev";
        "<leader>e" = "open_float";
      };

      lspBuf = {
        K = "hover";
        gd = "definition";
        gD = "declaration";
        gi = "implementation";
        gr = "references";
        gt = "type_definition";
        "<leader>ca" = "code_action";
        "<leader>rn" = "rename";
        "<leader>fs" = "document_symbol";
        "<leader>fS" = "workspace_symbol";
      };
    };

    # Configure LSP floating windows with rounded borders
    preConfig = ''
      local border = "rounded"

      vim.lsp.handlers["textDocument/hover"] = vim.lsp.with(
        vim.lsp.handlers.hover, { border = border }
      )

      vim.lsp.handlers["textDocument/signatureHelp"] = vim.lsp.with(
        vim.lsp.handlers.signature_help, { border = border }
      )

      vim.diagnostic.config({
        float = {
          border = border,
          source = true,
        },
        virtual_text = {
          prefix = "",
          spacing = 2,
        },
        signs = true,
        underline = true,
        update_in_insert = false,
        severity_sort = true,
      })
    '';

    onAttach = ''
      -- Enable inlay hints if supported
      if client.server_capabilities.inlayHintProvider then
        vim.lsp.inlay_hint.enable(true, { bufnr = bufnr })
      end
    '';
  };

  # Base formatting setup - language modules merge into this
  plugins.conform-nvim = {
    enable = true;
    settings = {
      format_on_save = {
        lsp_format = "fallback";
        timeout_ms = 2000;
      };

      formatters_by_ft = {
        "*" = ["trim_whitespace"];
        "_" = ["trim_newlines"];
      };
    };
  };

  keymaps = [
    {
      mode = "n";
      key = "<leader>cf";
      action = lib.nixvim.mkRaw ''
        function()
          require('conform').format({ async = true, lsp_format = 'fallback' })
        end
      '';
      options = {
        silent = true;
        desc = "Format buffer";
      };
    }
  ];

}

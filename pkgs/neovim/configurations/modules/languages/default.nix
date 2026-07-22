# Shared LSP infrastructure, common keymaps, and formatting base
# Import this alongside specific language modules (rust.nix, nix.nix, etc.)
{lib, pkgs, ...}: {
  # LSP-general which-key groups (owned here, since these prefixes are provided
  # by the shared LSP layer rather than any single language module).
  whichKeyGroups = [
    {__unkeyed = "g"; group = "Go";}
    {__unkeyed = "<leader>c"; group = "Code";}
    {__unkeyed = "<leader>d"; group = "Diagnostics";}
    {__unkeyed = "<leader>l"; group = "LSP";}
  ];

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
        "<leader>e" = "open_float";
      };

      lspBuf = {
        gD = "declaration";
        "<leader>rn" = "rename";
      };
    };

    # Configure LSP floating windows with rounded borders
    preConfig = ''
      local border = "rounded"

      vim.diagnostic.config({
        float = {
          border = border,
          source = true,
        },
        -- Full diagnostics as virtual lines below the current line only; keeps
        -- other lines uncluttered. Gutter signs still flag every affected line.
        virtual_text = false,
        virtual_lines = {
          current_line = true,
        },
        signs = true,
        underline = true,
        update_in_insert = false,
        severity_sort = true,
      })

      -- Toggle between current-line-only and all-lines virtual diagnostics,
      -- for surveying every diagnostic in a file then collapsing back.
      vim.keymap.set("n", "<leader>dl", function()
        local cfg = vim.diagnostic.config()
        local all = type(cfg.virtual_lines) == "table" and cfg.virtual_lines.current_line == nil
        vim.diagnostic.config({
          virtual_lines = all and { current_line = true } or true,
        })
      end, { silent = true, desc = "Toggle diagnostic virtual lines (all/current)" })
    '';

    onAttach = ''
      -- Enable inlay hints if supported
      if client.server_capabilities.inlayHintProvider then
        vim.lsp.inlay_hint.enable(true, { bufnr = bufnr })
      end

      -- List-based navigation via mini.pick (fuzzy + preview when multiple results)
      local function map(lhs, scope, desc)
        vim.keymap.set("n", lhs, function()
          require("mini.extra").pickers.lsp({ scope = scope })
        end, { buffer = bufnr, silent = true, desc = desc })
      end
      map("gd", "definition", "Definition")
      map("gr", "references", "References")
      map("gi", "implementation", "Implementation")
      map("gt", "type_definition", "Type definition")
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
      key = "K";
      action = lib.nixvim.mkRaw ''function() vim.lsp.buf.hover({ border = "rounded" }) end'';
      options = { silent = true; desc = "Hover"; };
    }
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
    # Diagnostic navigation via the modern vim.diagnostic.jump API
    # (goto_next/goto_prev are deprecated in Neovim 0.11+). Quiet: no float
    # popup on landing -- the current-line virtual_lines already show it.
    {
      mode = "n";
      key = "<leader>j";
      action = lib.nixvim.mkRaw "function() vim.diagnostic.jump({ count = 1 }) end";
      options = { silent = true; desc = "Next diagnostic"; };
    }
    {
      mode = "n";
      key = "<leader>k";
      action = lib.nixvim.mkRaw "function() vim.diagnostic.jump({ count = -1 }) end";
      options = { silent = true; desc = "Prev diagnostic"; };
    }
    {
      mode = "n";
      key = "]d";
      action = lib.nixvim.mkRaw "function() vim.diagnostic.jump({ count = 1 }) end";
      options = { silent = true; desc = "Next diagnostic"; };
    }
    {
      mode = "n";
      key = "[d";
      action = lib.nixvim.mkRaw "function() vim.diagnostic.jump({ count = -1 }) end";
      options = { silent = true; desc = "Prev diagnostic"; };
    }
  ];

  # Remove Neovim's built-in `gr`-prefix LSP maps (grn/gra/grr/gri/grt/grx).
  # They turn `gr` into a prefix, so our `gr` (references) waits for `timeoutlen`
  # and pops a which-key submenu on slow entry -- the exact speed-dependent
  # behavior we want to avoid. Our scheme already covers all of them:
  #   gd/gr/gi/gt navigation + <leader>ca (code action) + <leader>rn (rename).
  extraConfigLua = ''
    for _, key in ipairs({ "grn", "grr", "gri", "grt", "grx", "gra" }) do
      pcall(vim.keymap.del, "n", key)
      pcall(vim.keymap.del, "x", key)
    end
  '';
}

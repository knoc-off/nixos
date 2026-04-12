# Completion via blink.cmp + LuaSnip
# Enter to accept, Tab/S-Tab for snippet placeholder jumping
# Sources: LSP, snippets (LuaSnip + friendly-snippets), buffer, path
{lib, ...}: {
  # LuaSnip snippet engine
  plugins.luasnip = {
    enable = true;
    settings = {
      keep_roots = true;
      link_roots = true;
      link_children = true;
      update_events = "TextChanged,TextChangedI";
      region_check_events = "CursorMoved";
      delete_check_events = "TextChanged";
    };
  };

  # Community snippet collection -- nixvim auto-wires this into LuaSnip via fromVscode
  plugins.friendly-snippets.enable = true;

  plugins.blink-cmp = {
    enable = true;
    setupLspCapabilities = true;

    settings = {
      keymap = {
        preset = "enter";
        "<Tab>" = ["snippet_forward" "select_next" "fallback"];
        "<S-Tab>" = ["snippet_backward" "select_prev" "fallback"];
        "<C-j>" = ["select_next" "fallback"];
        "<C-k>" = ["select_prev" "fallback"];
      };

      completion = {
        list.selection = {
          preselect = true;
          auto_insert = true;
        };

        accept.auto_brackets.enabled = true;

        menu = {
          border = "rounded";
          scrollbar = true;
          draw = {
            treesitter = ["lsp"];
            columns = lib.nixvim.mkRaw ''
              { { "kind_icon" }, { "label", "label_description", gap = 1 }, { "source_name" } }
            '';
          };
        };

        documentation = {
          auto_show = true;
          auto_show_delay_ms = 200;
          window.border = "rounded";
        };

        ghost_text.enabled = true;
      };

      signature.enabled = true;

      snippets.preset = "luasnip";

      sources = {
        default = lib.nixvim.mkRaw ''
          function()
            local ok, in_comment = pcall(function()
              local cursor = vim.api.nvim_win_get_cursor(0)
              local row = cursor[1] - 1
              local col = math.max(0, cursor[2] - 1)
              for _, cap in ipairs(vim.treesitter.get_captures_at_pos(0, row, col)) do
                if cap.capture == "comment" then return true end
              end
              return false
            end)
            if ok and in_comment then
              return { "buffer", "path" }
            end
            return { "lsp", "snippets", "buffer", "path" }
          end
        '';
      };

      cmdline = {
        enabled = true;
        sources = ["cmdline" "buffer"];
        keymap = {
          "<Tab>" = ["accept"];
          "<CR>" = ["accept_and_enter" "fallback"];
        };
        completion.menu.auto_show = true;
      };

      appearance = {
        nerd_font_variant = "mono";
      };

      fuzzy.implementation = "prefer_rust";
    };
  };
}

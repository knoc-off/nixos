# Completion via blink.cmp
# Enter to accept, Tab/S-Tab for snippet placeholder jumping
# Sources: LSP, snippets, buffer, path
{lib, ...}: {
  plugins.blink-cmp = {
    enable = true;
    setupLspCapabilities = true;

    settings = {
      keymap = {
        "<CR>" = ["accept" "fallback"];
        "<C-space>" = ["show" "show_documentation" "hide_documentation"];
        "<C-e>" = ["hide" "fallback"];
        "<Tab>" = ["select_next" "snippet_forward" "fallback"];
        "<S-Tab>" = ["select_prev" "snippet_backward" "fallback"];
        "<C-j>" = ["select_next" "fallback"];
        "<C-k>" = ["select_prev" "fallback"];
        "<C-n>" = ["select_next" "fallback"];
        "<C-p>" = ["select_prev" "fallback"];
      };

      completion = {
        list.selection = {
          preselect = true;
          auto_insert = false;
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

      snippets.preset = "default";

      sources = {
        default = ["lsp" "snippets" "buffer" "path"];
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

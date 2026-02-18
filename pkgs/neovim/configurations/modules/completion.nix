# Completion via blink.cmp
# LSP-only for now -- extend with snippets, buffer, etc. later
{lib, ...}: {
  plugins.blink-cmp = {
    enable = true;
    setupLspCapabilities = true;

    settings = {
      keymap.preset = "super-tab";

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

      sources = {
        default = ["lsp" "path"];
        cmdline = [];
      };

      appearance = {
        nerd_font_variant = "mono";
        use_nvim_cmp_as_default = true;
      };

      fuzzy.implementation = "prefer_rust";
    };
  };
}

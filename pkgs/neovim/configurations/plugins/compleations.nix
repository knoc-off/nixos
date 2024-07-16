{
  config,
  lib,
  ...
}: {
  options.completeopt = ["menu" "menuone" "noselect"];

  config.plugins = {
    luasnip.enable = true;

    lspkind = {
      enable = true;

      cmp = {
        enable = true;
        menu = {
          nvim_lsp = "[LSP]";
          nvim_lua = "[api]";
          path = "[path]";
          luasnip = "[snip]";
          buffer = "[buffer]";
          neorg = "[neorg]";
          cmp_tabnine = "[TabNine]";
        };
        #} //
        #(if plugins.tabnine.enable then {cmp_tabnine = "[TabNine]"; } else {} );
        # if plugin is enabled then add to set
      };
    };

    cmp = {
      enable = true;

      settings = {
        snippet.expand = "function(args) require('luasnip').lsp_expand(args.body) end";

        mapping = {
          "<C-d>" = "cmp.mapping.scroll_docs(-4)";
          "<C-f>" = "cmp.mapping.scroll_docs(4)";
          "<C-Space>" = "cmp.mapping.complete()";
          "<C-e>" = "cmp.mapping.close()";

          "<Tab>" = ''
            cmp.mapping(function(fallback)
              if cmp.visible() then
                cmp.select_next_item()
              else
                fallback()
              end
            end, {'i', 's'})
          '';
          "<S-Tab>" = ''
            cmp.mapping(function(fallback)
              if cmp.visible() then
                cmp.select_prev_item()
              else
                fallback()
              end
            end, {'i', 's'})
          '';
          "<CR>" = ''
            cmp.mapping({
              i = function(fallback)
                if cmp.visible() and cmp.get_active_entry() then
                  cmp.confirm({ behavior = cmp.ConfirmBehavior.Replace, select = false })
                else
                  fallback()
                end
              end,
              s = cmp.mapping.confirm({ select = true }),
              c = cmp.mapping.confirm({ behavior = cmp.ConfirmBehavior.Replace, select = true }),
            })
          '';
        };

        sources = [
          {name = "path";}
          {name = "nvim_lsp";}
          {name = "cmp_tabnine";}
          {name = "luasnip";}
          {
            name = "buffer";
            # Words from other open buffers can also be suggested.
            option.get_bufnrs.__raw = "vim.api.nvim_list_bufs";
          }
          {name = "neorg";}
        ];
      };
    };
  };
}

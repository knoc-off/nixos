{ helpers, lib, theme, ... }:

{

  # putting each config in a set that gets imported.
  # this will later be split up into its own respective files.
  imports = [

    ./settings/options.nix
    ./settings/keymappings.nix

    # highlight.nix
    {

      match = {
        TODO = "TODO";
        ExtraWhitespace = "\\s\\+$";
        ahhhhh = "!\\{3,\\}";
      };

      highlight = {
        Todo = {
          fg = "#${theme.base07}";
          bg = "#${theme.base0A}";
        };
        ExtraWhitespace.bg = "#${theme.base01}";
        ahhhhh = {
          fg = "#${theme.base07}";
          bg = "#${theme.base08}";
        };
      };
    }

    # autocmd
    {
      autoCmd = [
        # Remove trailing whitespace on save
        {
          event = "BufWrite";
          command = "%s/\\s\\+$//e";
        }

      ];
    }

    {
      plugins.luasnip.enable = true;

      keymaps = [
        # Tab: Jump forward in a snippet, but only if able to do so (otherwise insert a tab)
        {
          mode = [ "i" "s" ]; # Insert and select modes
          key = "<Tab>";
          action = ''
            function()
              local ls = require("luasnip")
              if ls.expand_or_jumpable() then
                ls.expand_or_jump()
              else
                vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Tab>", true, false, true), "n", true)
              end
            end
          '';
          lua = true;
          desc = "LuaSnip: Expand or jump to next snippet field";
        }

        # Shift-Tab: Jump backward in a snippet, otherwise insert a shift-tab
        {
          mode = [ "i" "s" ];
          key = "<S-Tab>";
          action = ''
            function()
              local ls = require("luasnip")
              if ls.jumpable(-1) then
                ls.jump(-1)
              else
                vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<S-Tab>", true, false, true), "n", true)
              end
            end
          '';
          lua = true;
          desc = "LuaSnip: Jump to previous snippet field";
        }
      ];

    }

  ];

  viAlias = true;
  vimAlias = true;

  # plugin manager, that loads plugin with lua code
  luaLoader.enable = true;
}

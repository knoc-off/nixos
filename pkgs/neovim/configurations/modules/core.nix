# TODO: restructure this to have better scoping for each module.
{
  color-lib,
  lib,
  theme,
  pkgs,
  helpers,
  ...
}: {
  imports = [
    # highlight.nix
    {
      match =
        {
          TODO = "TODO";
          FIXME = "FIXME";
          HACK = "HACK";
          ExtraWhitespace = "\\s\\+$";
          ahhhhh = "!\\{3,\\}";
        }
        // lib.mapAttrs' (name: _: {
          name = "theme.${name}";
          value = "\\<theme.${name}\\>";
        })
        theme;

      highlight =
        {
          TODO = {
            fg = "#${theme.base00}";
            bg = "#${color-lib.setOkhsvValue 0.9 theme.base0A}";
          };
          FIXME = {
            fg = "#${theme.base00}";
            bg = "#${color-lib.setOkhsvValue 0.9 theme.base0E}";
          };
          HACK = {
            fg = "#${theme.base00}";
            bg = "#${color-lib.setOkhsvValue 0.9 theme.base0C}";
          };

          SnippetCursor = {
            # Use a distinct color, like green
            bg = "#${theme.base0B}";
            fg = "#${theme.base00}";
          };

          ExtraWhitespace.bg = "#${theme.base01}";
          ahhhhh = {
            fg = "#${theme.base07}";
            bg = "#${theme.base08}";
          };
        }
        // lib.mapAttrs' (name: color: {
          name = "theme.${name}";
          value = {
            bg = "#${color}";

            fg = "#${color-lib.ensureTextContrast color color 4.5}";
          };
        })
        theme;
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
    # open path under cursor
    {
      keymaps = [
        {
          mode = "n";
          key = "<S-CR>";
          action = helpers.mkRaw ''
            function()
              local path = vim.fn.expand('<cfile>')
              if path ~= "" then
                -- Get current file's directory or fallback to working directory
                local current_file = vim.fn.expand('%:p')
                local base_dir = current_file ~= ''' and vim.fn.fnamemodify(current_file, ':h') or vim.fn.getcwd()

                -- Resolve path relative to current file's location
                local is_absolute = path:sub(1, 1) == '/'
                local full_path = is_absolute
                  and path
                  or vim.fn.resolve(base_dir .. '/' .. path)

                -- Check if file/directory exists
                local stat = vim.loop.fs_stat(full_path)
                if stat then
                  vim.cmd('edit '..vim.fn.fnameescape(full_path))
                else
                  -- Try adding common extensions if needed
                  local extensions = { '.md', '.txt', ''' }
                  for _, ext in ipairs(extensions) do
                    local test_path = full_path .. ext
                    if vim.loop.fs_stat(test_path) then
                      vim.cmd('edit '..vim.fn.fnameescape(test_path))
                      return
                    end
                  end
                  vim.notify("Path not found: "..full_path, vim.log.levels.WARN)
                end
              end
            end
          '';
          options = {
            silent = true;
            desc = "Open path under cursor (relative to file location)";
          };
        }
      ];
    }
    # Tab-Bar
    {
      plugins.bufferline = {
        enable = true;
        settings.options = {
          truncateNames = true;
          diagnostics = "nvim_lsp";
        };
      };

      keymaps = let
        normal =
          lib.mapAttrsToList (key: action: {
            mode = "n";
            inherit action key;
          }) {
            #"<leader>bp" = ":BufferLinePick<CR>";
            #"<leader>bc" = ":bp | bd #<CR>";
            #"<leader>bP" = ":BufferLineTogglePin<CR>";
            #"<leader>bd" = ":BufferLineSortByDirectory<CR>";
            #"<leader>be" = ":BufferLineSortByExtension<CR>";
            #"<leader>bt" = ":BufferLineSortByTabs<CR>";
            #"<leader>bL" = ":BufferLineCloseRight<CR>";
            #"<leader>bH" = ":BufferLineCloseLeft<CR>";
            #"<leader><S-h>" = ":BufferLineMovePrev<CR>";
            #"<leader><S-l>" = ":BufferLineMoveNext<CR>";

            "<Tab>" = ":BufferLineCycleNext<CR>";
            "<S-Tab>" = ":BufferLineCyclePrev<CR>";
          };
      in
        helpers.keymaps.mkKeymaps {options.silent = true;} normal;
    }
    # Very useful
    # TODO: scope highlighting
    {
      plugins.indent-blankline = {
        enable = true;
        settings = {
          exclude = {
            filetypes = [
              "dashboard"
              "lspinfo"
              "packer"
              "checkhealth"
              "help"
              "man"
              "gitcommit"
              "TelescopePrompt"
              "TelescopeResults"
              "''"
            ];
          };
          indent = {char = "┊";};
        };
      };
    }
  ];
}

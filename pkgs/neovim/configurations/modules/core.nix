# TODO: restructure this to have better scoping for each module.
{
  color-lib,
  lib,
  theme,
  helpers,
  ...
}: {
  imports = [
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
          name = "theme.dark.${name}";
          value = "\\<theme\\.dark\\.${name}\\>";
        })
        theme.dark
        // lib.mapAttrs' (name: _: {
          name = "theme.light.${name}";
          value = "\\<theme\\.light\\.${name}\\>";
        })
        theme.light;

      highlight =
        {
          TODO = {
            fg = "#${theme.dark.base00}";
            bg = "#${color-lib.setOkhsvValue 0.9 theme.dark.base0A}";
          };
          FIXME = {
            fg = "#${theme.dark.base00}";
            bg = "#${color-lib.setOkhsvValue 0.9 theme.dark.base0E}";
          };
          HACK = {
            fg = "#${theme.dark.base00}";
            bg = "#${color-lib.setOkhsvValue 0.9 theme.dark.base0C}";
          };

          SnippetCursor = {
            # Use a distinct color, like green
            bg = "#${theme.dark.base0B}";
            fg = "#${theme.dark.base00}";
          };

          ExtraWhitespace.bg = "#${theme.dark.base01}";
          ahhhhh = {
            fg = "#${theme.dark.base07}";
            bg = "#${theme.dark.base08}";
          };
        }
        // lib.mapAttrs' (name: color: {
          name = "theme.dark.${name}";
          value = {
            bg = "#${color}";
            fg = "#${color-lib.ensureTextContrast color color 4.5}";
          };
        })
        theme.dark
        // lib.mapAttrs' (name: color: {
          name = "theme.light.${name}";
          value = {
            bg = "#${color}";
            fg = "#${color-lib.ensureTextContrast color color 4.5}";
          };
        })
        theme.light;
    }
    {
      autoCmd = [
        {
          event = "BufWrite";
          command = "%s/\\s\\+$//e";
        }
      ];
    }
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
          lib.mapAttrsToList
          (key: action: {
            mode = "n";
            inherit action key;
          })
          {
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

    {
      plugins.treesitter-context = {
        enable = true;
        settings = {
          enable = true;
          max_lines = 0;
          min_window_height = 0;
          line_numbers = true;
          multiline_threshold = 20;
          trim_scope = "outer";
          mode = "cursor";
          separator = null;
          zindex = 20;
        };
      };
    }

    {
      plugins.rainbow-delimiters = {
        enable = true;
        settings.highlight = [
          "RainbowDelimiterRed"
          "RainbowDelimiterYellow"
          "RainbowDelimiterBlue"
          "RainbowDelimiterOrange"
          "RainbowDelimiterGreen"
          "RainbowDelimiterViolet"
          "RainbowDelimiterCyan"
        ];
      };
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
          indent = {
            char = "┋";
          };

          scope = {
            enabled = true;
            char = "▎";
            show_start = true;
            show_end = true;
            include = {
              node_type = {
                "*" = [
                  "class"
                  "return_statement"
                  "function"
                  "method"
                  "^if"
                  "^while"
                  "jsx_element"
                  "^for"
                  "^object"
                  "^table"
                  "block"
                  "arguments"
                  "if_statement"
                  "else_clause"
                  "jsx_element"
                  "jsx_self_closing_element"
                  "try_statement"
                  "catch_clause"
                  "import_statement"
                  "operation_type"
                ];
              };
            };
          };
        };
      };
    }
  ];
}

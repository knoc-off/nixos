# TODO: restructure this to have better scoping for each module.
{
  color-lib,
  lib,
  theme,
  helpers,
  ...
}: let
  # Recursively flatten theme tree to create match patterns
  # Creates patterns like "theme_dark_base00" matching text "theme.dark.base00"
  # Takes both attrPrefix (with underscores) and textPrefix (with dots)
  flattenThemeToMatchesHelper = attrPrefix: textPrefix: attrs:
    lib.foldl' (
      acc: name: let
        value = attrs.${name};
        # Path with underscores for attribute names (valid Nix identifiers)
        attrPath =
          if attrPrefix == ""
          then name
          else "${attrPrefix}_${name}";
        # Original path with dots for matching text in files
        textPath =
          if textPrefix == ""
          then name
          else "${textPrefix}.${name}";
      in
        if builtins.isString value
        then
          acc
          // {
            ${attrPath} = textPath;
          }
        else acc // flattenThemeToMatchesHelper attrPath textPath value
    ) {} (builtins.attrNames attrs);

  flattenThemeToMatches = prefix: attrs:
    flattenThemeToMatchesHelper prefix prefix attrs;
in {
  imports = [
    {
      match =
        {
          # these are defined in the theme files.
          # ../themes/default.nix
          # for example:
          # highlights.ahhhhh = {
          #   fg = "$bg0";
          #   bg = "$red";
          # };

          TODO = "TODO";
          FIXME = "FIXME";
          HACK = "HACK";
          ExtraWhitespace = "\\s\\+$";
          ahhhhh = "!\\{3,\\}";
        }
        // flattenThemeToMatches "theme" theme;
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
      # can this be made into a format of like code-action highlights or something?
      # maybe a plugin, something that will highlight the links that can be followed?
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
    # Tab-Bar (shows vim tabs as layouts, not individual buffers)
    {
      plugins.bufferline = {
        enable = true;
        settings.options = {
          mode = "tabs";
          truncateNames = true;
          diagnostics = "nvim_lsp";
          show_duplicate_prefix = false;
          tab_size = 24;
          max_name_length = 24;
          separator_style = "slope";
          name_formatter = helpers.mkRaw ''
            function(buf)
              local tabnr = buf.tabnr
              local wins = vim.api.nvim_tabpage_list_wins(tabnr)
              local names = {}
              for _, win in ipairs(wins) do
                local bufnr = vim.api.nvim_win_get_buf(win)
                local name = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(bufnr), ':t')
                if name ~= "" and not vim.tbl_contains(names, name) then
                  table.insert(names, name)
                end
              end
              if #names == 0 then
                return "[New]"
              elseif #names == 1 then
                return names[1]
              else
                return table.concat(names, " | ")
              end
            end
          '';
        };
      };

      keymaps = [
        {
          mode = "n";
          key = "<Tab>";
          action = helpers.mkRaw ''
            function()
              if vim.fn.tabpagenr('$') > 1 then
                vim.cmd('tabnext')
              end
            end
          '';
          options = {
            silent = true;
            desc = "Next tab";
          };
        }
        {
          mode = "n";
          key = "<S-Tab>";
          action = helpers.mkRaw ''
            function()
              if vim.fn.tabpagenr('$') > 1 then
                vim.cmd('tabprev')
              end
            end
          '';
          options = {
            silent = true;
            desc = "Previous tab";
          };
        }
        {
          mode = "n";
          key = "<leader>tn";
          action = helpers.mkRaw ''
            function()
              vim.cmd('tabnew')
              vim.schedule(function()
                require('telescope.builtin').find_files()
              end)
            end
          '';
          options = {
            silent = true;
            desc = "New tab + find file";
          };
        }
        {
          mode = "n";
          key = "<leader>tc";
          action = helpers.mkRaw ''
            function()
              if vim.fn.tabpagenr('$') > 1 then
                vim.cmd('tabclose')
              else
                vim.notify("Cannot close last tab", vim.log.levels.WARN)
              end
            end
          '';
          options = {
            silent = true;
            desc = "Close tab";
          };
        }
      ];
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
    # Smooth animations
    {
      plugins.mini.modules.animate = {
        cursor.enable = false;
        scroll = {
          enable = true;
          timing = helpers.mkRaw "require('mini.animate').gen_timing.linear({ duration = 80, unit = 'total' })";
        };
        resize.enable = false;
        open.enable = false;
        close.enable = false;
      };
      opts.mousescroll = "ver:1,hor:1";
    }
  ];
}

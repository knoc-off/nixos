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

  # Recursively flatten theme tree to create highlight groups
  # Creates highlights like "theme_dark_base00" with bg = color value
  flattenThemeToHighlightsHelper = attrPrefix: attrs:
    lib.foldl' (
      acc: name: let
        value = attrs.${name};
        # Use underscores for attribute names
        attrPath =
          if attrPrefix == ""
          then name
          else "${attrPrefix}_${name}";
      in
        if builtins.isString value
        then
          acc
          // {
            ${attrPath} = {
              bg = "#${value}";
              fg = "#${color-lib.ensureTextContrast value value 4.5}";
            };
          }
        else acc // flattenThemeToHighlightsHelper attrPath value
    ) {} (builtins.attrNames attrs);

  flattenThemeToHighlights = prefix: attrs:
    flattenThemeToHighlightsHelper prefix attrs;
in {
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
        // flattenThemeToMatches "theme" theme;

      highlight = flattenThemeToHighlights "theme" theme;
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

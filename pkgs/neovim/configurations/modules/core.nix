# TODO: restructure this to have better scoping for each module.
{
  color-lib,
  lib,
  theme,
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
          event = "VimEnter";
          group = "AutoCd";
          callback = lib.nixvim.mkRaw ''
            function()
              -- Only run once per session
              if vim.g.cwd_set_this_session then
                return
              end

              local file_path = vim.api.nvim_buf_get_name(0)
              if file_path ~= "" then
                local target_dir
                if vim.fn.isdirectory(file_path) == 1 then
                  target_dir = file_path
                elseif vim.fn.filereadable(file_path) == 1 then
                  target_dir = vim.fn.fnamemodify(file_path, ":h")
                end

                if target_dir and vim.fn.isdirectory(target_dir) == 1 then
                  local current_cwd = vim.fn.getcwd()
                  if target_dir ~= current_cwd then
                    vim.cmd("cd " .. vim.fn.fnameescape(target_dir))
                    vim.g.cwd_set_this_session = true
                  end
                end
              end
            end
          '';
        }
      ];

      autoGroups.AutoCd.clear = true;
    }
    {
      keymaps = [
        {
          mode = "n";
          key = "<S-CR>";
          action = lib.nixvim.mkRaw ''
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
        {
          mode = "n";
          key = "q:";
          action = "<Nop>";
        }
      ];
    }
    {
      keymaps = [
        {
          mode = "n";
          key = "<leader>q";
          action = lib.nixvim.mkRaw ''
            function()
              vim.cmd('qall')
            end
          '';
          options = {
            silent = true;
            desc = "quit";
          };
        }
      ];
    }

    {
      plugins.treesitter = {
        enable = true;
        settings.highlight.enable = true;
      };
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

    # NOTE: rainbow-delimiters, indent-blankline, and vim-matchup moved to ./scope.nix
  ];
}

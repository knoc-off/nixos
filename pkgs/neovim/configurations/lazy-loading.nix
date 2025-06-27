{
  helpers,
  pkgs,
  lib,
  color-lib,
  theme,
  ...
}: {
  # putting each config in a set that gets imported.
  # this will later be split up into its own respective files.
  imports = [
    ./settings/options.nix
    ./settings/keymappings.nix
    ./themes

    {
      plugins.lz-n.enable = true;
    }

    # highlight.nix
    {
      match =
        {
          TODO = "TODO";
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

    {
      plugins.lspkind = {
        enable = true;
        cmp = {
          enable = true;
          menu = {luasnip = "[snip]";};
        };
      };

      plugins.luasnip.enable = true;
      plugins.friendly-snippets.enable = true;

      keymaps = [
        # Tab: Jump forward in a snippet, but only if able to do so (otherwise insert a tab)
        {
          mode = ["i" "s"]; # Insert and select modes
          key = "<Tab>";
          action = helpers.mkRaw ''
            function()
              local ls = require("luasnip")
              if ls.expand_or_jumpable() then
                ls.expand_or_jump()
              end
            end
          '';
        }

        # Shift-Tab: Jump backward in a snippet, otherwise insert a shift-tab
        {
          mode = ["i" "s"];
          key = "<S-Tab>";
          action = helpers.mkRaw ''
            function()
              local ls = require("luasnip")
              if ls.jumpable(-1) then
                ls.jump(-1)
              end
            end
          '';
        }

        # Ctrl-E: For changing choices in choiceNodes (next choice)
        {
          mode = ["i" "s"];
          key = "<C-E>";
          action = helpers.mkRaw ''
            function()
              local ls = require("luasnip")
              if ls.choice_active() then
                ls.next_choice()
              else
                vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<C-E>", true, false, true), "n", true)
              end
            end
          '';
        }
      ];

      plugins.cmp = {
        enable = true;
        settings = {
          # This tells cmp to use LuaSnip for expanding snippets
          snippet.expand = "function(args) require('luasnip').lsp_expand(args.body) end";

          mapping = {
            # <Tab>: Navigates cmp, then expands/jumps in LuaSnip, or inserts tab
            "<Tab>" = helpers.mkRaw ''
              cmp.mapping(function(fallback)
                if cmp.visible() then
                  cmp.select_next_item()
                elseif require("luasnip").expand_or_jumpable() then
                  require("luasnip").expand_or_jump()
                else
                  fallback()
                end
              end, {'i', 's'})
            '';

            # <S-Tab>: Navigates cmp backward, then jumps backward in LuaSnip, or inserts shift-tab
            "<S-Tab>" = helpers.mkRaw ''
              cmp.mapping(function(fallback)
                if cmp.visible() then
                  cmp.select_prev_item()
                elseif require("luasnip").jumpable(-1) then
                  require("luasnip").jump(-1)
                else
                  fallback()
                end
              end, {'i', 's'})
            '';

            # <C-e>: Cycles LuaSnip choices, or closes cmp, or default <C-e>
            "<C-e>" = helpers.mkRaw ''
              cmp.mapping(function(fallback)
                if require("luasnip").choice_active() then
                  require("luasnip").next_choice()
                else
                  cmp.mapping.close()(fallback)
                end
              end, {'i', 's'})
            '';

            "<CR>" = ''
              cmp.mapping.confirm({
                behavior = cmp.ConfirmBehavior.Insert,
                select = false,
              })
            '';
          };

          # Make sure 'luasnip' is listed as a source for snippets
          sources = [{name = "luasnip";}];
        };
      };
    }

    # Open file under the cursor
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

    # telescope
    {
      autoGroups.SetCWD = {};

      autoCmd = [
        {
          event = "BufReadPost";
          group = "SetCWD";
          callback = helpers.mkRaw ''
            function()
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
                  end
                end
              end
            end
          '';
        }
      ];

      plugins.mini.enable = true;
      plugins.mini.modules.icons = {
        default = {};
        directory = {};
        extension = {};
        file = {};
        filetype = {};
        lsp = {};
        os = {};

        use_file_extension =
          helpers.mkRaw "function(ext, file) return true end";

        style = "glyph";
      };
      plugins.mini.mockDevIcons = true;

      plugins.telescope = {
        lazyLoad = {
          settings = {
            cmd = "Telescope";
            keys = ["<leader>ff"];
          };
        };

        enable = true;

        keymaps = {
          # Find files using Telescope command-line sugar.
          "<leader>ff" = "find_files";
          "<leader>fg" = "live_grep";
          "<leader>b" = "buffers";
          "<leader>fh" = "help_tags";
          "<leader>fd" = "diagnostics";
          "<leader>fu" = "undo"; # Added undo keymap

          # FZF like bindings
          "<C-p>" = "git_files";
          "<leader>p" = "oldfiles";
          "<C-f>" = "live_grep";
        };

        settings.defaults = {
          file_ignore_patterns = [
            "^.git/"
            "^.mypy_cache/"
            "^__pycache__/"
            "^output/"
            "^data/"
            "%.ipynb"
          ];
          set_env.COLORTERM = "truecolor";
        };
      };
    }

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

    # Very useful. misc.
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

    {
      # Set indentation to 2 spaces for nix files
      autoCmd = [
        {
          event = "FileType";
          pattern = "nix";
          command = "setlocal tabstop=2 shiftwidth=2";
        }
      ];
      plugins.treesitter = {
        enable = true;
        # settings.ensure_installed = [ "" ]; # Backup
        settings = {
          highlight = {
            enable = true;

            disable = helpers.mkRaw ''
              function(lang, buf)
                  local max_filesize = 100 * 1024 -- 100 KB
                  local ok, stats = pcall(vim.loop.fs_stat, vim.api.nvim_buf_get_name(buf))
                  if ok and stats and stats.size > max_filesize then
                      return true
                  end
              end
            '';

            additional_vim_regex_highlighting = false;
          };
          incremental_selection = {
            enable = true;
            keymaps = {
              init_selection = "gnn";
              node_incremental = "grn";
              scope_incremental = "grc";
              node_decremental = "grm";
            };
          };
          # indent = { enable = true; };
        };
        grammarPackages = with pkgs.vimPlugins.nvim-treesitter.builtGrammars; [
          bash
          json
          lua
          make
          markdown
          nix
          regex
          toml
          vim
          vimdoc
          xml
          yaml
        ];
      };
    }
    {
      plugins.lint = {
        enable = true;
        autoCmd = {
          event = ["BufWritePost" "InsertLeave"];
          callback = helpers.mkRaw ''
            function()
              require('lint').try_lint()
            end

          '';
        };

        # Define linters with their packages included
        linters = {
          # Nix linters
          statix = {cmd = lib.getExe pkgs.statix;};
          deadnix = {cmd = lib.getExe pkgs.deadnix;};

          # Shell
          shellcheck = {cmd = lib.getExe pkgs.shellcheck;};

          # Web/Config formats
          jsonlint = {cmd = lib.getExe pkgs.nodePackages.jsonlint;};
          yamllint = {cmd = lib.getExe pkgs.yamllint;};
          markdownlint = {
            cmd = lib.getExe pkgs.nodePackages.markdownlint-cli;
            args = ["--disable" "MD013" "--"]; # Disable line length rule
          };

          # Python
          ruff = {
            cmd = lib.getExe pkgs.ruff;
            args = ["check" "--select" "E,W,F" "--quiet" "--stdin-filename"];
            stdin = true;
            append_fname = false;
          };

          # Docker
          hadolint = {cmd = lib.getExe pkgs.hadolint;};

          # Optional: Text linting (heavier)
          vale = {cmd = lib.getExe pkgs.vale;};
        };

        lintersByFt = {
          # Nix
          nix = ["statix" "deadnix"];

          # Shell scripts
          bash = ["shellcheck"];
          sh = ["shellcheck"];
          zsh = ["shellcheck"];

          # Web/Config formats
          json = ["jsonlint"];
          yaml = ["yamllint"];
          markdown = ["markdownlint"];

          # Programming languages
          python = ["ruff"];

          # Docker
          dockerfile = ["hadolint"];

          # Text/Documentation (if you want vale)
          # text = [ "vale" ];
          # gitcommit = [ "vale" ];
        };
      };
    }

    {
      plugins.conform-nvim = {
        enable = true;

        settings = {
          # Format on save with reasonable timeouts
          format_on_save = {
            lsp_format = "fallback";
            timeout_ms = 2000;
            quiet = false;
            stop_after_first = false;
          };

          # Backup formatting after save for slower formatters
          format_after_save = {
            lsp_format = "fallback";
            timeout_ms = 5000;
            quiet = true;
          };

          # Configure formatters by file type (matching your linters)
          formatters_by_ft = {
            # Nix
            nix = ["alejandra"];

            # Shell scripts
            bash = ["shfmt"];
            sh = ["shfmt"];
            zsh = ["shfmt"];

            # Web/Config formats
            json = ["prettier"];
            yaml = ["prettier"];
            yml = ["prettier"];
            markdown = ["prettier"];

            # Python
            python = ["isort" "black"];

            # Lua (for your nvim config)
            lua = ["stylua"];

            # Universal formatters for all files
            "*" = ["trim_whitespace"];
            "_" = ["trim_newlines"];
          };

          # Custom formatter configurations with proper executable paths
          formatters = {
            alejandra = {command = lib.getExe pkgs.alejandra;};
            shfmt = {
              command = lib.getExe pkgs.shfmt;
              args = [
                "-i"
                "2"
                "-ci"
                "-sr"
              ]; # 2 spaces, indent switch cases, simplify redirect
            };
            prettier = {
              command = lib.getExe pkgs.nodePackages.prettier;
              args = ["--stdin-filepath" "$FILENAME"];
            };
            black = {
              command = lib.getExe pkgs.black;
              args = ["--quiet" "-"];
            };
            isort = {
              command = lib.getExe pkgs.isort;
              args = ["--profile" "black" "--quiet" "-"];
            };
            stylua = {
              command = lib.getExe pkgs.stylua;
              args = ["--indent-type" "Spaces" "--indent-width" "2" "-"];
            };
            trim_whitespace = {
              command = lib.getExe' pkgs.coreutils "sed";
              args = ["s/[[:space:]]*$//"];
            };
            trim_newlines = {
              command = lib.getExe' pkgs.coreutils "sed";
              args = ["/^$/N;/\\n$/d"];
            };
          };

          # Logging and notifications
          log_level = "warn";
          notify_on_error = true;
          notify_no_formatters =
            false; # Don't spam for files without formatters
        };
      };

      # Add keymaps for manual formatting
      keymaps = [
        {
          mode = "n";
          key = "<leader>cf";
          action =
            helpers.mkRaw
            "function() require('conform').format({ async = true, lsp_format = 'fallback' }) end";
          options = {
            silent = true;
            desc = "Format buffer";
          };
        }
      ];
    }
  ];

  viAlias = true;
  vimAlias = true;

  # plugin manager, that loads plugin with lua code
  luaLoader.enable = true;
}

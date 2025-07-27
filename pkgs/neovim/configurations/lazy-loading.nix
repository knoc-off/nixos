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
    ./modules/core.nix

    {
      # Lazy loading
      plugins.lz-n.enable = true;
    }

    {
      # tag:core
      plugins = {
        lspkind = {
          enable = true;
          cmp = {
            enable = true;
            menu = {luasnip = "[snip]";};
          };
        };
        cmp-nvim-lsp.enable = true;
        cmp-buffer.enable = true;
        cmp-path.enable = true;
        cmp-nvim-lua.enable = true; # For nvim config editing

        luasnip = {
          enable = true;
        };

        friendly-snippets.enable = true;
      };

      keymaps = [
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

      extraConfigLuaPre = ''
        _G.IN_SNIPPET_MODE = false
      '';
      plugins = {
        cmp = {
          enable = true;
          settings = {
            # This tells cmp to use LuaSnip for expanding snippets

            snippet.expand = "function(args) require('luasnip').lsp_expand(args.body)  end";

            # Enable ghost text for inline previews
            experiment.ghost_text = true;

            mapping = {
              "<Tab>" = helpers.mkRaw ''
                cmp.mapping(function(fallback)
                  local ls = require("luasnip")
                  local copilot_suggestion = require("copilot.suggestion")

                  if cmp.visible() then
                    -- Priority 1: If completion menu is open, navigate it.
                    cmp.select_next_item()
                  elseif _G.IN_SNIPPET_MODE then
                    -- Priority 2: If we are in snippet mode, handle the snippet.
                    if ls.jumpable(1) then
                      ls.jump(1)
                    end
                    -- NOTE: If not jumpable (at the end), we do nothing.
                    -- This "swallows" the Tab keypress and prevents the fallback.
                  elseif copilot_suggestion.is_visible() then
                    -- Priority 3: If a Copilot suggestion is visible, accept it.
                    copilot_suggestion.accept()
                  else
                    -- Priority 4: If none of the above, insert a literal tab.
                    fallback()
                  end
                end, { "i", "s" })
              '';

              "<S-Tab>" = helpers.mkRaw ''
                cmp.mapping(function(fallback)
                  local ls = require("luasnip")
                  if cmp.visible() then
                    cmp.select_prev_item()
                  elseif _G.IN_SNIPPET_MODE and ls.jumpable(-1) then
                    -- Only jump back if we are in snippet mode
                    ls.jump(-1)
                  else
                    -- No fallback for Shift-Tab
                  end
                end, { "i", "s" })
              '';

              "<CR>" = helpers.mkRaw ''
                cmp.mapping.confirm({
                  behavior = cmp.ConfirmBehavior.Insert,
                  select = false,
                })
              '';

              "<C-e>" = helpers.mkRaw ''
                cmp.mapping(function(fallback)
                  if require("luasnip").choice_active() then
                    require("luasnip").next_choice()
                  else
                    if cmp.visible() then
                      cmp.close()
                    else
                      fallback()
                    end
                  end
                end, { "i", "s" })
              '';
            };
            # Make sure 'luasnip' is listed as a source for snippets
            sources = [
              {name = "nvim_lsp";} # Source for LSP suggestions
              {name = "luasnip";} # Source for snippets
              {name = "copilot";}
              {name = "buffer";} # Source for text from the current buffer
              {name = "path";} # Source for file system paths
            ];
          };
        };
      };
    }

    {
      # tag:misc
      plugins.nvim-autopairs.enable = true;

      # This part is important for making <CR> work correctly with cmp and autopairs
      extraConfigLua = ''
        local cmp_autopairs = require('nvim-autopairs.completion.cmp')
        local cmp = require('cmp')
        cmp.event:on(
          'confirm_done',
          cmp_autopairs.on_confirm_done()
        )
      '';
    }
    {
      # tag:file-specific
      autoCmd = [
        # Launch OpenSCAD when opening .scad files
        {
          event = "BufWinEnter";
          pattern = "*.scad";
          callback = helpers.mkRaw ''
            function(args)
              if vim.b[args.buf].openscad_job then
                return
              end

              local filepath = vim.fn.expand('%:p')
              local jid = vim.fn.jobstart(
                { "openscad", filepath },
                {
                  detach = true,
                  on_stdout = function() end,
                  on_stderr = function() end,
                }
              )

              vim.b[args.buf].openscad_job = jid
              vim.notify(
                'Launched OpenSCAD for ' .. vim.fn.fnamemodify(filepath, ':t'),
                vim.log.levels.INFO
              )
            end
          '';
        }

        # Close OpenSCAD when leaving .scad files
        {
          event = "BufWinLeave";
          pattern = "*.scad";
          callback = helpers.mkRaw ''
            function(args)
              local jid = vim.b[args.buf].openscad_job
              if jid then
                vim.fn.jobstop(jid)
                vim.b[args.buf].openscad_job = nil
                vim.notify(
                  'Closed OpenSCAD for ' .. vim.fn.fnamemodify(vim.fn.expand('%:p'), ':t'),
                  vim.log.levels.INFO
                )
              end
            end
          '';
        }

        # Clean up any remaining OpenSCAD processes on Neovim exit
        {
          event = "VimLeavePre";
          pattern = "*";
          callback = helpers.mkRaw ''
            function()
              for _, buf in ipairs(vim.api.nvim_list_bufs()) do
                local ok, jid = pcall(vim.api.nvim_buf_get_var, buf, 'openscad_job')
                if ok and jid then
                  pcall(vim.fn.jobstop, jid)
                end
              end
            end
          '';
        }
      ];
    }

    # telescope TODO: split this block up.
    {
      autoGroups.SetCWD = {};

      autoCmd = [
        {
          event = "VimEnter"; # Changed from BufReadPost to VimEnter
          group = "SetCWD";
          callback = helpers.mkRaw ''
            function()
              -- Only run if we haven't set CWD yet this session
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

      extraConfigLuaPre = ''
        -- Directory stack for pushd/popd functionality
        _G.dir_stack = {}

        -- Function to push current directory and change to new one
        _G.pushd = function(new_dir)
          if new_dir and vim.fn.isdirectory(new_dir) == 1 then
            table.insert(_G.dir_stack, vim.fn.getcwd())
            vim.cmd("cd " .. vim.fn.fnameescape(new_dir))
            vim.notify("Pushed to: " .. new_dir, vim.log.levels.INFO)
          end
        end

        -- Function to pop directory from stack
        _G.popd = function()
          if #_G.dir_stack > 0 then
            local prev_dir = table.remove(_G.dir_stack)
            vim.cmd("cd " .. vim.fn.fnameescape(prev_dir))
            vim.notify("Popped to: " .. prev_dir, vim.log.levels.INFO)
          else
            vim.notify("Directory stack is empty", vim.log.levels.WARN)
          end
        end

        -- Function to find git root
        _G.find_git_root = function()
          local current_dir = vim.fn.expand('%:p:h')
          if current_dir == "" then
            current_dir = vim.fn.getcwd()
          end

          local git_root = vim.fn.systemlist("git -C " .. vim.fn.shellescape(current_dir) .. " rev-parse --show-toplevel")[1]
          if vim.v.shell_error == 0 and git_root then
            return git_root
          end
          return nil
        end

        -- Function to cd to git root
        _G.cd_to_git_root = function()
          local git_root = _G.find_git_root()
          if git_root then
            _G.pushd(git_root)
          else
            vim.notify("Not in a git repository", vim.log.levels.WARN)
          end
        end
      '';

      keymaps = [
        {
          mode = "n";
          key = "<leader>gr";
          action = helpers.mkRaw "_G.cd_to_git_root";
          options = {
            silent = true;
            desc = "CD to git root";
          };
        }
        {
          mode = "n";
          key = "<leader>cd";
          action = helpers.mkRaw "function()
            _G.pushd(vim.fn.expand('%:p:h'))

            end";
          options = {
            silent = true;
            desc = "CD current file";
          };
        }
        {
          mode = "n";
          key = "<leader>pd";
          action = helpers.mkRaw "_G.popd";
          options = {
            silent = true;
            desc = "Pop directory (go back)";
          };
        }
      ];

      plugins.telescope = {
        lazyLoad = {
          settings = {
            cmd = "Telescope";
            keys = ["<leader>ff"];
          };
        };

        enable = true;

        keymaps = {
          "<leader>ff" = "find_files";
          "<leader>fg" = "live_grep";
          "<leader>b" = "buffers";
          "<leader>fh" = "help_tags";
          "<leader>fd" = "diagnostics";
          "<leader>fu" = "undo";

          "<leader>lr" = "lsp_references";
          "<leader>ld" = "lsp_definitions";
          "<leader>li" = "lsp_implementations";
          "<leader>lt" = "lsp_type_definitions";
          "<leader>ls" = "lsp_document_symbols";
          "<leader>lw" = "lsp_workspace_symbols";

          "<C-p>" = "git_files";
          "<leader>p" = "oldfiles";
          "<C-f>" = "live_grep";
        };

        settings = {
          defaults = {
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
      };
    }

    {
      # tag:file-specific
      autoCmd = [
        {
          event = "FileType";
          pattern = "nix";
          command = "setlocal tabstop=2 shiftwidth=2";
        }
      ];

      # tag: core
      plugins.treesitter = {
        enable = true;
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
        };
        grammarPackages = with pkgs.vimPlugins.nvim-treesitter.builtGrammars; [
          bash
          json
          lua
          make
          markdown
          typst
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

    # tag: linting
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

        linters = {
          statix = {cmd = lib.getExe pkgs.statix;};
          deadnix = {cmd = lib.getExe pkgs.deadnix;};

          shellcheck = {cmd = lib.getExe pkgs.shellcheck;};

          jsonlint = {cmd = lib.getExe pkgs.nodePackages.jsonlint;};
          yamllint = {cmd = lib.getExe pkgs.yamllint;};
          tflint = {cmd = lib.getExe pkgs.tflint;}; # terraform
          markdownlint = {
            cmd = lib.getExe pkgs.nodePackages.markdownlint-cli;
            args = ["--disable" "MD013" "--"]; # Disable line length rule
          };

          ruff = {
            cmd = lib.getExe pkgs.ruff;
            args = ["check" "--select" "E,W,F" "--quiet" "--stdin-filename"];
            stdin = true;
            append_fname = false;
          };

          hadolint = {cmd = lib.getExe pkgs.hadolint;};
          vale = {cmd = lib.getExe pkgs.vale;};
        };

        lintersByFt = {
          nix = ["statix" "deadnix"];

          terraform = ["tflint"];

          bash = ["shellcheck"];
          sh = ["shellcheck"];
          zsh = ["shellcheck"];

          json = ["jsonlint"];
          yaml = ["yamllint"];
          markdown = ["markdownlint"];
          python = ["ruff"];
          dockerfile = ["hadolint"];
        };
      };
    }

    # tag: file-specific
    {
      plugins.typst-preview = {
        lazyLoad.settings.ft = ["typst"];
        enable = true;
      };
    }

    # tag: file-specific
    {
      plugins.rustaceanvim = {
        enable = true;

        settings = {
          server = {
            default_settings = {
              rust-analyzer = {
                cargo = {
                  allFeatures = true;
                  buildScripts.enable = true;
                  loadOutDirsFromCheck = true;
                };

                diagnostics = {
                  enable = true;
                  enableExperimental = true;
                };

                inlayHints = {
                  enable = true;
                  typeHints = {
                    enable = true;
                    hideClosureInitialization = false;
                    hideNamedConstructor = false;
                  };
                  parameterHints.enable = true;
                  chainingHints.enable = true;
                };

                completion = {
                  addCallArgumentSnippets = true;
                  addCallParenthesis = true;
                  postfix.enable = true;
                  autoimport.enable = true;
                };

                procMacro.enable = true;

                checkOnSave = true;
              };
            };
          };

          tools = {
            hover_actions = {
              replace_builtin_hover = true;
            };

            code_actions = {
              ui_select_fallback = true;
            };

            float_win_config = {
              border = "rounded";
            };
          };

          # (Debug Adapter Protocol)
          # dap = {
          #   adapter = {
          #     type = "executable";
          #     command = "${pkgs.lldb}/bin/lldb-vscode";
          #     name = "lldb";
          #   };
          # };
        };
      };
    }

    # FIXME: This is not good, needs to be consolidated
    {
      keymaps = [
        {
          mode = "n";
          key = "gr";
          action = helpers.mkRaw ''
            function()
              require('telescope.builtin').lsp_references()
            end
          '';
          options = {
            silent = true;
            desc = "LSP References";
          };
        }
        {
          mode = "n";
          key = "gd";
          action = helpers.mkRaw ''
            function()
              require('telescope.builtin').lsp_definitions()
            end
          '';
          options = {
            silent = true;
            desc = "LSP Definitions";
          };
        }
        {
          mode = "n";
          key = "gD";
          action = helpers.mkRaw ''
            function()
              require('telescope.builtin').lsp_definitions()
            end
          '';
          options = {
            silent = true;
            desc = "LSP Definitions";
          };
        }
        {
          mode = "n";
          key = "gi";
          action = helpers.mkRaw ''
            function()
              require('telescope.builtin').lsp_implementations()
            end
          '';
          options = {
            silent = true;
            desc = "LSP Implementations";
          };
        }
        {
          mode = "n";
          key = "gt";
          action = helpers.mkRaw ''
            function()
              require('telescope.builtin').lsp_type_definitions()
            end
          '';
          options = {
            silent = true;
            desc = "LSP Type Definitions";
          };
        }

        {
          mode = "n";
          key = "<leader>ci";
          action = helpers.mkRaw ''
            function()
              print(vim.inspect(require('conform').list_formatters(0)))
            end
          '';
          options = {
            silent = false;
            desc = "Show available formatters for current buffer";
          };
        }
        {
          mode = "n";
          key = "<leader>cl";
          action = helpers.mkRaw ''
            function()
              vim.cmd('ConformInfo')
            end
          '';
          options = {
            silent = true;
            desc = "Show Conform info";
          };
        }
      ];

      plugins = {
        # tag:lsp/linter?
        lsp = {
          # lazyLoad.settings.ft = ["openscad" "typst" "rust"];
          enable = true;
          servers = {
            openscad_lsp.enable = true;
            tinymist.enable = true;

            ts_ls.enable = true;
          };
          keymaps = {
            silent = true;
            diagnostic = {
              "<leader>j" = "goto_next";
              "<leader>k" = "goto_prev";
            };

            lspBuf = {
              K = "hover";
              "<leader>ca" = "code_action";
              "<leader>rn" = "rename";
            };
          };
        };

        lsp-format.enable = true;
      };
    }

    {
      # tag:formatting
      plugins.conform-nvim = {
        enable = true;

        settings = {
          format_on_save = {
            lsp_format = "fallback";
            timeout_ms = 2000;
            quiet = false;
            stop_after_first = false;
          };

          format_after_save = {
            lsp_format = "fallback";
            timeout_ms = 5000;
            quiet = true;
          };

          formatters_by_ft = {
            nix = ["alejandra"];

            bash = ["shfmt"];
            sh = ["shfmt"];
            zsh = ["shfmt"];

            json = ["prettier"];
            yaml = ["prettier"];
            yml = ["prettier"];
            markdown = ["prettier"];

            python = ["isort" "black"];

            lua = ["stylua"];

            rust = ["rustfmt"];

            javascript = ["prettier"];
            typescript = ["prettier"];
            typescriptreact = ["prettier"];

            # Universal formatters for all files
            "*" = ["trim_whitespace"];
            "_" = ["trim_newlines"];
          };

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

            rustfmt = {
              command = lib.getExe pkgs.rustfmt;
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
        {
          mode = "n";
          key = "<leader>e";
          action = helpers.mkRaw "vim.diagnostic.open_float";
          options = {
            silent = true;
            desc = "Show line diagnostics";
          };
        }
      ];
    }

    # tag:ai-trash/plugins
    {
      plugins = {
        copilot-lua.enable = true;
        copilot-cmp.enable = true;
        copilot-chat.enable = true;
      };

      plugins.copilot-lua = {
        settings = {
          panel.enable = false;
          suggestion = {
            auto_trigger = false;
            enabled = false;
            keymap = {
              accept = false;
              next = false;
              prev = false;
              dismiss = false;
            };
          };
        };
      };
    }
  ];

  viAlias = true;
  vimAlias = true;

  # plugin manager, that loads plugin with lua code
  luaLoader.enable = true;
}

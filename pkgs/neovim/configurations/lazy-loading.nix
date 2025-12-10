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
    ./themes/default.nix
    ./modules/core.nix

    # Theme toggle functionality
    {
      extraConfigLuaPre = let
        # Generate dark theme colors
        darkTheme = theme.dark;
        # Generate light theme colors
        lightTheme = theme.light;
      in ''
        -- Store both theme configurations
        _G.theme_dark = {
          style = "dark",
          transparent = true,
          colors = {
            bg0 = "#${darkTheme.base00}",
            bg1 = "#${color-lib.adjustOkhslLightness 0.03 darkTheme.base00}",
            bg2 = "#${color-lib.adjustOkhslLightness 0.06 darkTheme.base00}",
            bg3 = "#${color-lib.adjustOkhslLightness 0.09 darkTheme.base00}",
            fg = "#${darkTheme.base05}",
            grey = "#${darkTheme.base03}",
            light_grey = "#${darkTheme.base04}",
            red = "#${darkTheme.base08}",
            orange = "#${darkTheme.base09}",
            yellow = "#${darkTheme.base0A}",
            green = "#${darkTheme.base0B}",
            cyan = "#${darkTheme.base0C}",
            blue = "#${darkTheme.base0D}",
            purple = "#${darkTheme.base0E}",
            dark_red = "#${color-lib.adjustOkhslLightness (-0.1) darkTheme.base08}",
            dark_orange = "#${color-lib.adjustOkhslLightness (-0.1) darkTheme.base09}",
            dark_yellow = "#${color-lib.adjustOkhslLightness (-0.1) darkTheme.base0A}",
            dark_green = "#${color-lib.adjustOkhslLightness (-0.1) darkTheme.base0B}",
            dark_cyan = "#${color-lib.adjustOkhslLightness (-0.1) darkTheme.base0C}",
            dark_blue = "#${color-lib.adjustOkhslLightness (-0.1) darkTheme.base0D}",
            dark_purple = "#${color-lib.adjustOkhslLightness (-0.1) darkTheme.base0E}",
            bright_red = "#${color-lib.adjustOkhslLightness 0.1 darkTheme.base08}",
            bright_orange = "#${color-lib.adjustOkhslLightness 0.1 darkTheme.base09}",
            bright_yellow = "#${color-lib.adjustOkhslLightness 0.1 darkTheme.base0A}",
            bright_green = "#${color-lib.adjustOkhslLightness 0.1 darkTheme.base0B}",
            bright_cyan = "#${color-lib.adjustOkhslLightness 0.1 darkTheme.base0C}",
            bright_blue = "#${color-lib.adjustOkhslLightness 0.1 darkTheme.base0D}",
            bright_purple = "#${color-lib.adjustOkhslLightness 0.1 darkTheme.base0E}",
            diff_add = "#${color-lib.adjustOkhslSaturation (-0.2) darkTheme.base0B}",
            diff_change = "#${color-lib.adjustOkhslSaturation (-0.2) darkTheme.base0D}",
            diff_delete = "#${color-lib.adjustOkhslSaturation (-0.2) darkTheme.base08}",
          }
        }

        _G.theme_light = {
          style = "light",
          transparent = false,
          colors = {
            bg0 = "#${lightTheme.base00}",
            bg1 = "#${color-lib.adjustOkhslLightness (-0.03) lightTheme.base00}",
            bg2 = "#${color-lib.adjustOkhslLightness (-0.06) lightTheme.base00}",
            bg3 = "#${color-lib.adjustOkhslLightness (-0.09) lightTheme.base00}",
            fg = "#${lightTheme.base05}",
            grey = "#${lightTheme.base03}",
            light_grey = "#${lightTheme.base04}",
            red = "#${lightTheme.base08}",
            orange = "#${lightTheme.base09}",
            yellow = "#${lightTheme.base0A}",
            green = "#${lightTheme.base0B}",
            cyan = "#${lightTheme.base0C}",
            blue = "#${lightTheme.base0D}",
            purple = "#${lightTheme.base0E}",
            dark_red = "#${color-lib.adjustOkhslLightness (-0.1) lightTheme.base08}",
            dark_orange = "#${color-lib.adjustOkhslLightness (-0.1) lightTheme.base09}",
            dark_yellow = "#${color-lib.adjustOkhslLightness (-0.1) lightTheme.base0A}",
            dark_green = "#${color-lib.adjustOkhslLightness (-0.1) lightTheme.base0B}",
            dark_cyan = "#${color-lib.adjustOkhslLightness (-0.1) lightTheme.base0C}",
            dark_blue = "#${color-lib.adjustOkhslLightness (-0.1) lightTheme.base0D}",
            dark_purple = "#${color-lib.adjustOkhslLightness (-0.1) lightTheme.base0E}",
            bright_red = "#${color-lib.adjustOkhslLightness 0.1 lightTheme.base08}",
            bright_orange = "#${color-lib.adjustOkhslLightness 0.1 lightTheme.base09}",
            bright_yellow = "#${color-lib.adjustOkhslLightness 0.1 lightTheme.base0A}",
            bright_green = "#${color-lib.adjustOkhslLightness 0.1 lightTheme.base0B}",
            bright_cyan = "#${color-lib.adjustOkhslLightness 0.1 lightTheme.base0C}",
            bright_blue = "#${color-lib.adjustOkhslLightness 0.1 lightTheme.base0D}",
            bright_purple = "#${color-lib.adjustOkhslLightness 0.1 lightTheme.base0E}",
            diff_add = "#${color-lib.adjustOkhslSaturation (-0.2) lightTheme.base0B}",
            diff_change = "#${color-lib.adjustOkhslSaturation (-0.2) lightTheme.base0D}",
            diff_delete = "#${color-lib.adjustOkhslSaturation (-0.2) lightTheme.base08}",
          }
        }

        -- Track current theme
        _G.current_theme_mode = "dark"

        -- Function to toggle between light and dark themes
        _G.toggle_theme = function()
          local onedark = require('onedark')

          if _G.current_theme_mode == "dark" then
            onedark.setup(_G.theme_light)
            onedark.load()
            _G.current_theme_mode = "light"
            vim.notify("Switched to light theme", vim.log.levels.INFO)
          else
            onedark.setup(_G.theme_dark)
            onedark.load()
            _G.current_theme_mode = "dark"
            vim.notify("Switched to dark theme", vim.log.levels.INFO)
          end
        end
      '';

      keymaps = [
        {
          mode = "n";
          key = "<leader>tt";
          action = helpers.mkRaw "_G.toggle_theme";
          options = {
            silent = true;
            desc = "Toggle between light and dark theme";
          };
        }
      ];
    }

    {
      plugins.fidget.enable = true;
    }

    {
      # Lazy loading
      plugins.lz-n.enable = true;
    }

    {
      #plugins gitsigns
      plugins.gitsigns = {
        enable = true;
        settings = {
          diff_opts = {
            vertical = true;
          };
        };
      };

      # Initialize gitsigns base state tracking
      extraConfigLuaPre = ''
        -- Track gitsigns base state: 'HEAD' or 'merge-base'
        _G.gitsigns_base_state = 'HEAD'
      '';

      keymaps = [
        {
          mode = "n";
          key = "<leader>gm"; # or whatever key you prefer
          action = helpers.mkRaw ''
            function()
              local gs = require('gitsigns')

              if _G.gitsigns_base_state == 'HEAD' then
                -- Switch to merge-base
                local merge_base = vim.fn.system('git merge-base HEAD origin/main'):gsub('\n', ''')

                if vim.v.shell_error == 0 and merge_base ~= "" then
                  gs.change_base(merge_base, true)
                  _G.gitsigns_base_state = 'merge-base'
                  vim.notify('Gitsigns base set to merge-base with origin/main (' .. merge_base:sub(1,8) .. ')', vim.log.levels.INFO)
                else
                  vim.notify('Failed to get merge-base with origin/main. Are you in a git repo with origin/main?', vim.log.levels.WARN)
                end
              else
                -- Switch back to HEAD
                gs.change_base(nil, true)
                _G.gitsigns_base_state = 'HEAD'
                vim.notify('Gitsigns base reset to HEAD', vim.log.levels.INFO)
              end
            end
          '';
          options = {
            silent = true;
            desc = "Toggle Gitsigns base (HEAD ↔ merge-base with origin/main)";
          };
        }
      ];
    }

    {
      # Split this up to place the descriptors in the right spot
      plugins.which-key = let
        keymapAttrsToWhichKeySpec = attrs: lib.mapAttrsToList (key: value: {__unkeyed-1 = key;} // value) attrs;
      in {
        enable = true;

        settings = {
          preset = false;
          delay = 200;

          spec = keymapAttrsToWhichKeySpec {
            # Gitsigns
            "<leader>gm" = {
              desc = "Toggle merge-base diff";
              icon = " ";
            };
            "<leader>b" = {
              group = "Buffers";
              icon = "󰓩 ";
            };
            "<leader>f" = {
              group = "Files";
              icon = "󰈞 ";
            };
            "<leader>ff" = {
              desc = "Find Files";
              icon = "󰱽 ";
            };
            "<leader>fg" = {
              desc = "Live Grep";
              icon = " ";
            };
            "<leader>fh" = {
              desc = "Help Tags";
              icon = "󰋖 ";
            };
            "<leader>fd" = {
              desc = "Diagnostics";
              icon = " ";
            };
            "<leader>fu" = {
              desc = "Undo History";
              icon = "⎌ ";
            };
            "<leader>a" = {
              desc = "Code Action";
              icon = " ";
            };
            "<leader>ca" = {
              desc = "LSP Code Action";
              icon = " ";
            };
            "<leader>rn" = {
              desc = "LSP Rename";
              icon = " ";
            };
            "<leader>j" = {
              desc = "LSP Diagnostic Next";
              icon = " ";
            };
            "<leader>k" = {
              desc = "LSP Diagnostic Prev";
              icon = " ";
            };
            "<leader>cf" = {
              desc = "Format Buffer";
              icon = " ";
            };
            "<leader>cl" = {
              desc = "Show Conform info";
              icon = " ";
            };
            "<leader>gr" = {
              desc = "CD to git root";
              icon = " ";
            };
            "<leader>gb" = {
              desc = "Git Blame popup";
              icon = " ";
            };
            "<leader>cd" = {
              desc = "CD current file";
              icon = " ";
            };
            "<leader>cD" = {
              desc = "CD parent directory";
              icon = " ";
            };
            "<leader>pd" = {
              desc = "Pop directory (go back)";
              icon = " ";
            };
            "<leader>cp" = {
              desc = "Copy current file path";
              icon = " ";
            };
            "<leader>e" = {
              desc = "Show line diagnostics";
              icon = " ";
            };
            "<leader>ci" = {
              desc = "Show available formatters";
              icon = " ";
            };
            "<leader>l" = {
              group = "LSP";
              icon = " ";
            };
            "<leader>ld" = {
              desc = "Go to Definition";
              icon = " ";
            };
            "<leader>lD" = {
              desc = "Go to Declaration";
              icon = " ";
            };
            "<leader>li" = {
              desc = "List Implementations";
              icon = " ";
            };
            "<leader>lr" = {
              desc = "Show References";
              icon = " ";
            };
            "<leader>lh" = {
              desc = "Show Hover";
              icon = "󰋖 ";
            };
            "<leader>ls" = {
              desc = "Document Symbols";
              icon = " ";
            };
            "<leader>lS" = {
              desc = "Signature Help";
              icon = " ";
            };
            "<leader>ln" = {
              desc = "Rename Symbol";
              icon = " ";
            };
            "<leader>lf" = {
              desc = "Format Code";
              icon = " ";
            };
            "<leader>lt" = {
              desc = "Type Definition";
              icon = " ";
            };
            "<C-E>" = {
              mode = [
                "i"
                "s"
              ];
              desc = "Next snippet choice / default <C-E>";
              icon = " ";
            };
            "<leader>tt" = {
              desc = "Toggle light/dark theme";
              icon = "󰔎 ";
            };
          };

          win.border = "single";

          notify = false;
        };
      };
    }

    {
      plugins.treesitter-textobjects = {
        enable = true;

        settings = {
          # Text object selection
          select = {
            enable = true;
            lookahead = true;

            keymaps = {
              # Functions
              af = "@function.outer";
              "if" = "@function.inner";

              # Classes
              ac = "@class.outer";
              ic = "@class.inner";

              # Parameters/arguments
              ap = "@parameter.outer";
              ip = "@parameter.inner";

              # Conditionals
              ai = "@conditional.outer";
              ii = "@conditional.inner";

              # Loops
              al = "@loop.outer";
              il = "@loop.inner";

              # Comments
              "a/" = "@comment.outer";
              "i/" = "@comment.inner";

              # Blocks
              ab = "@block.outer";
              ib = "@block.inner";
            };

            selection_modes = {
              "@parameter.outer" = "v"; # charwise
              "@function.outer" = "V"; # linewise
              "@class.outer" = "V"; # linewise
            };

            include_surrounding_whitespace = false;
          };

          # Swap text objects
          swap = {
            enable = true;

            swap_next = {
              "<leader>a" = "@parameter.inner";
              "<leader>f" = "@function.outer";
            };

            swap_previous = {
              "<leader>A" = "@parameter.inner";
              "<leader>F" = "@function.outer";
            };
          };

          # Movement between text objects
          move = {
            enable = true;
            set_jumps = true; # Set jumps in the jumplist

            goto_next_start = {
              "]f" = "@function.outer";
              "]c" = "@class.outer";
              "]p" = "@parameter.inner";
            };

            goto_next_end = {
              "]F" = "@function.outer";
              "]C" = "@class.outer";
              "]P" = "@parameter.inner";
            };

            goto_previous_start = {
              "[f" = "@function.outer";
              "[c" = "@class.outer";
              "[p" = "@parameter.inner";
            };

            goto_previous_end = {
              "[F" = "@function.outer";
              "[C" = "@class.outer";
              "[P" = "@parameter.inner";
            };
          };

          # LSP interop for peeking definitions
          lsp_interop = {
            enable = true;
            border = "rounded";

            peek_definition_code = {
              "<leader>df" = "@function.outer";
              "<leader>dF" = "@class.outer";
            };

            floating_preview_opts = {
              border = "rounded";
              max_width = 80;
              max_height = 20;
            };
          };
        };
      };
    }
    {
      # tag:core
      plugins = {
        lspkind = {
          enable = true;
          settings.cmp = {
            enable = true;
            menu = {
              luasnip = "[snip]";
            };
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
          mode = [
            "i"
            "s"
          ];
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
        {
          mode = [
            "i"
            "s"
          ];
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

                  if cmp.visible() then
                    -- Priority 1: If completion menu is open, navigate it.
                    cmp.select_next_item()
                  elseif _G.IN_SNIPPET_MODE then
                    -- Priority 2: If we are in snippet mode, handle the snippet.
                    if ls.jumpable(1) then
                      ls.jump(1)
                    end
                  else
                    -- Priority 3: If none of the above, insert a literal tab.
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
              {name = "buffer";} # Source for text from the current buffer
              {name = "path";} # Source for file system paths
            ];
          };
        };
      };
    }

    {
      plugins.nvim-surround.enable = true;
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

    # mini sessions
    {
      plugins.mini.enable = true;
      plugins.mini-sessions = {
        enable = true;
        settings = {
          autoread = false;
          autowrite = true;
          directory = helpers.mkRaw "vim.fn.stdpath('data') .. '/sessions'";
          file = "";
          force = {
            read = false;
            write = true;
            delete = false;
          };
          verbose = {
            read = true;
            write = true;
            delete = true;
          };
        };
      };

      extraConfigLuaPre = ''
        -- Session management helpers (marks-like: m1 to save, '1 to load)
        _G.save_session_slot = function(slot)
          local MiniSessions = require('mini.sessions')
          local name = "slot_" .. slot
          MiniSessions.write(name)
          vim.notify("Session saved to slot " .. slot, vim.log.levels.INFO)
        end

        _G.load_session_slot = function(slot)
          local MiniSessions = require('mini.sessions')
          local name = "slot_" .. slot
          if MiniSessions.detected[name] then
            MiniSessions.read(name)
            vim.notify("Session loaded from slot " .. slot, vim.log.levels.INFO)
          else
            vim.notify("No session in slot " .. slot, vim.log.levels.WARN)
          end
        end

        _G.save_session_named = function()
          vim.ui.input({ prompt = "Session name: " }, function(name)
            if name and name ~= "" then
              require('mini.sessions').write(name)
              vim.notify("Session saved: " .. name, vim.log.levels.INFO)
            end
          end)
        end

        _G.load_session_picker = function()
          local MiniSessions = require('mini.sessions')
          local sessions = vim.tbl_keys(MiniSessions.detected)
          if #sessions == 0 then
            vim.notify("No sessions found", vim.log.levels.WARN)
            return
          end
          table.sort(sessions)
          vim.ui.select(sessions, { prompt = "Load session:" }, function(choice)
            if choice then
              MiniSessions.read(choice)
            end
          end)
        end

        _G.delete_session_picker = function()
          local MiniSessions = require('mini.sessions')
          local sessions = vim.tbl_keys(MiniSessions.detected)
          if #sessions == 0 then
            vim.notify("No sessions found", vim.log.levels.WARN)
            return
          end
          table.sort(sessions)
          vim.ui.select(sessions, { prompt = "Delete session:" }, function(choice)
            if choice then
              MiniSessions.delete(choice)
              vim.notify("Session deleted: " .. choice, vim.log.levels.INFO)
            end
          end)
        end
      '';

      keymaps = [
        # Save: <leader>s + slot or 's' for named
        {
          mode = "n";
          key = "<leader>ss";
          action = helpers.mkRaw "_G.save_session_named";
          options = {
            silent = true;
            desc = "Save session (named)";
          };
        }
        {
          mode = "n";
          key = "<leader>s1";
          action = helpers.mkRaw "function() _G.save_session_slot(1) end";
          options = {
            silent = true;
            desc = "Save session slot 1";
          };
        }
        {
          mode = "n";
          key = "<leader>s2";
          action = helpers.mkRaw "function() _G.save_session_slot(2) end";
          options = {
            silent = true;
            desc = "Save session slot 2";
          };
        }
        {
          mode = "n";
          key = "<leader>s3";
          action = helpers.mkRaw "function() _G.save_session_slot(3) end";
          options = {
            silent = true;
            desc = "Save session slot 3";
          };
        }
        # Load: <leader>S + slot, or 'l' to pick
        {
          mode = "n";
          key = "<leader>sl";
          action = helpers.mkRaw "_G.load_session_picker";
          options = {
            silent = true;
            desc = "Load session (pick)";
          };
        }
        {
          mode = "n";
          key = "<leader>S1";
          action = helpers.mkRaw "function() _G.load_session_slot(1) end";
          options = {
            silent = true;
            desc = "Load session slot 1";
          };
        }
        {
          mode = "n";
          key = "<leader>S2";
          action = helpers.mkRaw "function() _G.load_session_slot(2) end";
          options = {
            silent = true;
            desc = "Load session slot 2";
          };
        }
        {
          mode = "n";
          key = "<leader>S3";
          action = helpers.mkRaw "function() _G.load_session_slot(3) end";
          options = {
            silent = true;
            desc = "Load session slot 3";
          };
        }
        # Delete
        {
          mode = "n";
          key = "<leader>sd";
          action = helpers.mkRaw "_G.delete_session_picker";
          options = {
            silent = true;
            desc = "Delete session";
          };
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

        use_file_extension = helpers.mkRaw "function(ext, file) return true end";

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
          key = "<leader>gb";
          action = helpers.mkRaw "function() require('gitsigns').blame_line({ full = false }) end";
          options = {
            silent = true;
            desc = "Git Blame (popup)";
          };
        }
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
          key = "<leader>cD";
          action = helpers.mkRaw "function()
            _G.pushd(vim.fn.getcwd())
            vim.cmd('cd ..')
          end";
          options = {
            silent = true;
            desc = "CD parent directory";
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
        {
          mode = "n";
          key = "<leader>cp";
          action = helpers.mkRaw ''
            function()
              local path = vim.fn.expand('%:p')
              if path ~= "" then
                vim.fn.setreg('+', path)
                vim.notify("Copied to clipboard: " .. path, vim.log.levels.INFO)
              else
                vim.notify("No file in current buffer", vim.log.levels.WARN)
              end
            end
          '';
          options = {
            silent = true;
            desc = "Copy current file path";
          };
        }
      ];

      plugins.telescope = {
        lazyLoad = {
          enable = false;
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
        lazyLoad = {
          enable = true;
          settings.ft = [
            "openscad"
            "typst"
          ];
        };

        enable = true;

        autoCmd = {
          event = [
            "BufWritePost"
            "InsertLeave"
          ];
          callback = helpers.mkRaw ''
            function()
              -- Only run if lint is loaded (for lazy-loaded filetypes)
              local lint_ok, lint = pcall(require, 'lint')
              if lint_ok then
                lint.try_lint()
              end
            end
          '';
        };

        linters = {
          # statix = {
          #   cmd = lib.getExe pkgs.statix;
          # };
          deadnix = {
            cmd = lib.getExe pkgs.deadnix;
          };

          shellcheck = {
            cmd = lib.getExe pkgs.shellcheck;
          };

          jsonlint = {
            cmd = lib.getExe pkgs.nodePackages.jsonlint;
          };
          yamllint = {
            cmd = lib.getExe pkgs.yamllint;
          };
          tflint = {
            cmd = lib.getExe pkgs.tflint;
          }; # terraform
          markdownlint = {
            cmd = lib.getExe pkgs.nodePackages.markdownlint-cli;
            args = [
              "--disable"
              "MD013"
              "--"
            ]; # Disable line length rule
          };

          ruff = {
            cmd = lib.getExe pkgs.ruff;
            args = [
              "check"
              "--select"
              "E,W,F"
              "--quiet"
              "--stdin-filename"
            ];
            stdin = true;
            append_fname = false;
          };

          hadolint = {
            cmd = lib.getExe pkgs.hadolint;
          };
          vale = {
            cmd = lib.getExe pkgs.vale;
          };
        };

        lintersByFt = {
          nix = [
            #"statix"
            "deadnix"
          ];

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

    {
      plugins.rustaceanvim = {
        enable = true;

        settings = {
          server = {
            default_settings = {
              rust-analyzer = {
                imports = {
                  granularity = {
                    group = "module";
                  };
                  prefix = "self";
                };

                cargo = {
                  allFeatures = true;
                  buildScripts.enable = true;
                  loadOutDirsFromCheck = true;
                };

                diagnostics = {
                  enable = true;
                  # Disabled experimental - can cause slowness
                  enableExperimental = false;
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

                typing = {
                  continueCommentsOnNewline = false;
                };
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
            nil_ls.enable = true;
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

        # Disabled: conform-nvim handles all formatting to avoid conflicts
        # lsp-format.enable = true;
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

            python = [
              "isort"
              "black"
            ];

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
            alejandra = {
              command = lib.getExe pkgs.alejandra;
            };
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
              args = [
                "--stdin-filepath"
                "$FILENAME"
              ];
            };
            black = {
              command = lib.getExe pkgs.black;
              args = [
                "--quiet"
                "-"
              ];
            };
            isort = {
              command = lib.getExe pkgs.isort;
              args = [
                "--profile"
                "black"
                "--quiet"
                "-"
              ];
            };
            stylua = {
              command = lib.getExe pkgs.stylua;
              args = [
                "--indent-type"
                "Spaces"
                "--indent-width"
                "2"
                "-"
              ];
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
          notify_no_formatters = false; # Don't spam for files without formatters
        };
      };

      keymaps = [
        {
          mode = "n";
          key = "<leader>cf";
          action = helpers.mkRaw "function() require('conform').format({ async = true, lsp_format = 'fallback' }) end";
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
    # Avante.nvim - AI copilot like Cursor AI IDE
    {
      plugins.avante = {
        enable = true;

        lazyLoad = {
          enable = false;
          settings = {
            keys = [
              "<leader>aa"
              "<leader>ae"
              "<leader>ar"
              "<leader>at"
            ];
          };
        };

        settings = {
          provider = "claude";
          behaviour = {
            auto_suggestions = false;
            auto_set_highlight_group = true;
            auto_set_keymaps = true;
            auto_apply_diff_after_generation = false;
            #support_paste_from_clipboard = false;
          };

          mappings = {
            # ask = "<leader>aa";
            edit = "<leader>ae";
            refresh = "<leader>ar";
            diff = {
              ours = "co";
              theirs = "ct";
              both = "cb";
              all_theirs = "ca";
              cursor = "cc";
              next = "]x";
              prev = "[x";
            };
            jump = {
              next = "]]";
              prev = "[[";
            };
            submit = {
              normal = "<CR>";
              insert = "<C-s>";
            };
            toggle = {
              default = "<leader>at";
              debug = "<leader>ad";
              hint = "<leader>ah";
            };
          };

          hints = {
            enabled = false;
          };

          windows = {
            position = "right";
            wrap = true;
            width = 30;
            sidebar_header = {
              align = "center";
              rounded = true;
            };

            edit = {
              border = "rounded";
              start_insert = false;
            };
            ask = {
              start_insert = false;
            };
          };
        };
      };

      extraConfigLua = ''
        vim.opt.laststatus = 3
      '';

      keymaps = [
        {
          mode = [
            "n"
            "v"
          ];
          key = "<leader>aa";
          action = helpers.mkRaw ''
            function()
              -- Check if we're in visual mode or have a selection
              local mode = vim.fn.mode()
              local has_selection = mode == 'v' or mode == 'V' or mode == '\22' -- \22 is visual block mode

              if mode == 'n' and not has_selection then
                -- In normal mode with no selection, check if avante panel is open
                local avante = require('avante')
                if avante.is_sidebar_open() then
                  avante.close_sidebar()
                  return
                end
              end

              -- Otherwise, proceed with ask functionality
              require('avante.api').ask({ new_chat = true })
            end
          '';
          options = {
            desc = "avante: ask (or close if panel open)";
            silent = true;
          };
        }
        {
          mode = "v";
          key = "<leader>ae";
          action = helpers.mkRaw "function() require('avante.api').edit() end";
          options = {
            desc = "avante: edit";
            silent = true;
          };
        }
        {
          mode = "n";
          key = "<leader>ar";
          action = helpers.mkRaw "function() require('avante.api').refresh() end";
          options = {
            desc = "avante: refresh";
            silent = true;
          };
        }
        {
          mode = "n";
          key = "<leader>at";
          action = helpers.mkRaw "function() require('avante').toggle() end";
          options = {
            desc = "avante: toggle";
            silent = true;
          };
        }
      ];
    }
  ];

  viAlias = true;
  vimAlias = true;

  luaLoader.enable = true;
}

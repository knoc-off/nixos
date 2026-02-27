# Rust development environment
# - rustaceanvim (rust-analyzer integration)
# - rustfmt formatting
# - Rust-specific keymaps
{
  lib,
  pkgs,
  ...
}: {
  plugins.rustaceanvim = {
    enable = true;

    settings = {
      server = {
        # Use lspmux client shim - inherits direnv environment (PATH with rust-analyzer)
        # The client shim passes the environment to lspmux server, which spawns
        # the correct per-project rust-analyzer from your devshell
        # Requires: services.lspmux.enable = true in NixOS config
        cmd = ["lspmux" "client"];

        default_settings = {
          rust-analyzer = {
            imports = {
              granularity.group = "module";
              prefix = "self";
            };

            cargo = {
              allFeatures = false;
              allTargets = false;
              buildScripts.enable = true;
              loadOutDirsFromCheck = true;
              # Separate target dir prevents cargo build from invalidating RA cache
              targetDir = "target/rust-analyzer";
            };

            # Exclude directories from file watching (reduces inotify load)
            files = {
              excludeDirs = [
                ".direnv"
                ".git"
                "target"
                "node_modules"
                ".cargo"
              ];
            };

            lru.capacity = 256;

            checkOnSave = true;
            diagnostics = {
              enable = true;
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
              closingBraceHints = {
                enable = true;
                minLines = 25;
              };
              lifetimeElisionHints = {
                enable = "skip_trivial";
                useParameterNames = true;
              };
            };

            completion = {
              addCallArgumentSnippets = true;
              addCallParenthesis = true;
              postfix.enable = true;
              autoimport.enable = true;
              fullFunctionSignatures.enable = true;
            };

            procMacro.enable = true;

            typing.continueCommentsOnNewline = false;

            lens = {
              enable = true;
              references = {
                adt.enable = true;
                enumVariant.enable = true;
                method.enable = true;
                trait.enable = true;
              };
              run.enable = true;
              debug.enable = true;
              implementations.enable = true;
            };

            hover = {
              actions = {
                enable = true;
                references.enable = true;
                run.enable = true;
                debug.enable = true;
                gotoTypeDef.enable = true;
                implementations.enable = true;
              };
              documentation.enable = true;
              links.enable = true;
            };

            semanticHighlighting = {
              operator.specialization.enable = true;
              punctuation = {
                enable = true;
                specialization.enable = true;
              };
            };
          };
        };

        # Called fresh on every RustAnalyzer start — injects RA_TARGET into
        # cargo.target so the lspmux instance and RA settings stay in sync.
        settings = lib.nixvim.mkRaw ''
          function(project_root, default_settings)
            default_settings["rust-analyzer"].cargo.target = vim.env.RA_TARGET
            return default_settings
          end
        '';

        # Standalone file support (for single .rs files outside cargo projects)
        standalone = true;
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
        inlay_hints = {
          auto = true;
        };
      };
    };
  };

  plugins.conform-nvim.settings = {
    formatters_by_ft.rust = ["rustfmt"];
    formatters.rustfmt = {
      command = lib.getExe pkgs.rustfmt;
    };
  };

  keymaps = [
    {
      mode = "n";
      key = "<leader>rh";
      action = lib.nixvim.mkRaw ''
        function()
          vim.cmd.RustLsp({ 'hover', 'actions' })
        end
      '';
      options = {
        silent = true;
        desc = "Rust: Hover actions";
      };
    }
    {
      mode = "n";
      key = "<leader>ra";
      action = lib.nixvim.mkRaw ''
        function()
          vim.cmd.RustLsp('codeAction')
        end
      '';
      options = {
        silent = true;
        desc = "Rust: Code action";
      };
    }
    {
      mode = "n";
      key = "<leader>rr";
      action = lib.nixvim.mkRaw ''
        function()
          vim.cmd.RustLsp('runnables')
        end
      '';
      options = {
        silent = true;
        desc = "Rust: Runnables";
      };
    }
    {
      mode = "n";
      key = "<leader>rd";
      action = lib.nixvim.mkRaw ''
        function()
          vim.cmd.RustLsp('debuggables')
        end
      '';
      options = {
        silent = true;
        desc = "Rust: Debuggables";
      };
    }
    {
      mode = "n";
      key = "<leader>rt";
      action = lib.nixvim.mkRaw ''
        function()
          vim.cmd.RustLsp('testables')
        end
      '';
      options = {
        silent = true;
        desc = "Rust: Testables";
      };
    }
    {
      mode = "n";
      key = "<leader>rm";
      action = lib.nixvim.mkRaw ''
        function()
          vim.cmd.RustLsp('expandMacro')
        end
      '';
      options = {
        silent = true;
        desc = "Rust: Expand macro";
      };
    }
    {
      mode = "n";
      key = "<leader>rc";
      action = lib.nixvim.mkRaw ''
        function()
          vim.cmd.RustLsp('openCargo')
        end
      '';
      options = {
        silent = true;
        desc = "Rust: Open Cargo.toml";
      };
    }
    {
      mode = "n";
      key = "<leader>rp";
      action = lib.nixvim.mkRaw ''
        function()
          vim.cmd.RustLsp('parentModule')
        end
      '';
      options = {
        silent = true;
        desc = "Rust: Parent module";
      };
    }
    {
      mode = "n";
      key = "<leader>rj";
      action = lib.nixvim.mkRaw ''
        function()
          vim.cmd.RustLsp('joinLines')
        end
      '';
      options = {
        silent = true;
        desc = "Rust: Join lines";
      };
    }
    {
      mode = "n";
      key = "<leader>re";
      action = lib.nixvim.mkRaw ''
        function()
          vim.cmd.RustLsp('explainError')
        end
      '';
      options = {
        silent = true;
        desc = "Rust: Explain error";
      };
    }
    {
      mode = "n";
      key = "<leader>rD";
      action = lib.nixvim.mkRaw ''
        function()
          vim.cmd.RustLsp('renderDiagnostic')
        end
      '';
      options = {
        silent = true;
        desc = "Rust: Render diagnostic";
      };
    }
    {
      mode = "n";
      key = "<leader>rT";
      action = lib.nixvim.mkRaw ''
        function()
          require('rust-target').pick()
        end
      '';
      options = {
        silent = true;
        desc = "Rust: Switch cargo target";
      };
    }
  ];

  extraConfigLua = ''
    do
      local M = {}

      local common_targets = {
        "x86_64-pc-windows-gnu",
        "x86_64-pc-windows-msvc",
        "x86_64-unknown-linux-gnu",
        "x86_64-unknown-linux-musl",
        "aarch64-unknown-linux-gnu",
        "aarch64-unknown-linux-musl",
        "aarch64-apple-darwin",
        "wasm32-unknown-unknown",
        "wasm32-wasi",
        "thumbv7em-none-eabihf",
        "riscv32imc-unknown-none-elf",
      }

      -- Cache for full rustc target list
      local all_targets_cache = nil

      local function get_all_targets()
        if all_targets_cache then
          return all_targets_cache
        end
        local result = vim.fn.systemlist("rustc --print target-list 2>/dev/null")
        if vim.v.shell_error == 0 and #result > 0 then
          all_targets_cache = result
        else
          all_targets_cache = {}
        end
        return all_targets_cache
      end

      --- Switch the RA cargo target via lspmux env fingerprinting.
      --- Pass nil or "" to unset (native target).
      function M.switch(target)
        if target == "" then
          target = nil
        end

        local prev = vim.env.RA_TARGET
        vim.env.RA_TARGET = target

        -- Stop tears down the lspmux client pipe, start spawns a new one
        -- that inherits the updated RA_TARGET env → lspmux routes to the
        -- matching instance (or spawns a fresh one). The server.settings
        -- function reads RA_TARGET on each start to keep cargo.target in sync.
        vim.cmd("RustAnalyzer stop")
        vim.defer_fn(function()
          vim.cmd("RustAnalyzer start")
          local display = target or "native"
          local verb = prev and "Switched" or "Set"
          if not target then
            verb = "Cleared"
            display = "native"
          end
          vim.notify(verb .. " rust-analyzer target → " .. display, vim.log.levels.INFO)
        end, 200)
      end

      function M.pick()
        local items = { { label = "native (unset)", target = nil } }
        for _, t in ipairs(common_targets) do
          table.insert(items, { label = t, target = t })
        end

        vim.ui.select(items, {
          prompt = "Rust cargo target:",
          format_item = function(item)
            local current = vim.env.RA_TARGET
            local marker = ""
            if (item.target == nil and current == nil) or (item.target == current) then
              marker = " ● "
            end
            return item.label .. marker
          end,
        }, function(choice)
          if choice then
            M.switch(choice.target)
          end
        end)
      end

      function M.complete(lead)
        local results = {}
        local seen = {}

        -- Common targets first
        for _, t in ipairs(common_targets) do
          if t:find(lead, 1, true) == 1 then
            table.insert(results, t)
            seen[t] = true
          end
        end

        -- Then full rustc list
        for _, t in ipairs(get_all_targets()) do
          if not seen[t] and t:find(lead, 1, true) == 1 then
            table.insert(results, t)
          end
        end

        return results
      end

      -- Register module so the keymap can require() it
      package.loaded["rust-target"] = M

      vim.api.nvim_create_user_command("RustTarget", function(opts)
        M.switch(opts.args)
      end, {
        nargs = "?",
        complete = function(lead)
          return M.complete(lead)
        end,
        desc = "Switch rust-analyzer cargo target (via lspmux). No args = native.",
      })
    end
  '';
}

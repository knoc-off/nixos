# Rust development environment
# - rustaceanvim (rust-analyzer integration)
# - rustfmt formatting
# - Rust-specific keymaps
{lib, pkgs, ...}: {
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
  ];
}

# Debug Adapter Protocol (DAP) — debugger client + UI.
#
# Architecture (three separable pieces):
#   - nvim-dap        : the client. Speaks DAP, owns breakpoints/stepping/state.
#   - an adapter      : per-language bridge to the real debugger. For Rust this is
#                       codelldb (LLDB wrapper), provided on PATH via extraPackages.
#   - a configuration : "what to launch/attach to". We do NOT hand-write these:
#                       rustaceanvim auto-detects codelldb on PATH and registers
#                       Rust debug adapter+configs when rust-analyzer attaches, so
#                       <leader>rd (RustLsp debuggables) just works.
#
# UI is nvim-dap-view (single plugin): scopes, watches, breakpoints, call stack,
# REPL, terminal, plus inline virtual-text variable values. auto_toggle opens it
# on session start and closes it on exit.
{
  lib,
  pkgs,
  ...
}:
{
  whichKeyGroups = [
    {
      __unkeyed = "<leader>d";
      group = "Debug";
    }
  ];

  # Puts `codelldb` on PATH. nixpkgs compiles it from source (properly linked,
  # no FHS/marketplace-blob issues) — this is the NixOS path the rustaceanvim
  # README points at. rustaceanvim's adapter fn checks executable('codelldb').
  extraPackages = [ pkgs.vscode-extensions.vadimcn.vscode-lldb.adapter ];

  plugins.dap = {
    enable = true;

    # Gutter signs. texthl ties them to diagnostic-ish highlight groups so they
    # read as red (breakpoint) / yellow (stopped) without extra hl definitions.
    signs = {
      dapBreakpoint = {
        text = "●";
        texthl = "DiagnosticError";
      };
      dapBreakpointCondition = {
        text = "◆";
        texthl = "DiagnosticWarn";
      };
      dapLogPoint = {
        text = "◆";
        texthl = "DiagnosticInfo";
      };
      dapStopped = {
        text = "▶";
        texthl = "DiagnosticOk";
        linehl = "Visual";
      };
      dapBreakpointRejected = {
        text = "○";
        texthl = "DiagnosticError";
      };
    };
  };

  plugins.dap-view = {
    enable = true;
    settings = {
      # Inline virtual-text: shows each variable's value next to its source line
      # as you step. The single most useful thing for *seeing* data flow.
      # (requires nvim 0.12+, which we're on)
      virtual_text.enabled = true;
      # Open the view on session start, close it on exit — no manual toggling.
      auto_toggle = true;
      winbar.controls.enabled = true;
    };
  };

  keymaps =
    let
      mk = key: fn: desc: {
        mode = "n";
        inherit key;
        action = lib.nixvim.mkRaw "function() ${fn} end";
        options = {
          silent = true;
          inherit desc;
        };
      };
    in
    [
      # Flow control. F-keys follow the VSCode convention every nvim-dap tutorial
      # uses, so external docs match. <leader>d* duplicates for discoverability.
      (mk "<F5>" "require('dap').continue()" "Debug: continue / start")
      (mk "<leader>dc" "require('dap').continue()" "Continue / start")
      (mk "<F10>" "require('dap').step_over()" "Debug: step over")
      (mk "<leader>do" "require('dap').step_over()" "Step over")
      (mk "<F11>" "require('dap').step_into()" "Debug: step into")
      (mk "<leader>di" "require('dap').step_into()" "Step into")
      (mk "<S-F11>" "require('dap').step_out()" "Debug: step out")
      (mk "<leader>dO" "require('dap').step_out()" "Step out")
      (mk "<S-F5>" "require('dap').terminate()" "Debug: terminate")
      (mk "<leader>dt" "require('dap').terminate()" "Terminate")
      (mk "<leader>dr" "require('dap').run_last()" "Run last")
      (mk "<leader>dR" "require('dap').restart()" "Restart")

      # Breakpoints.
      (mk "<F9>" "require('dap').toggle_breakpoint()" "Debug: toggle breakpoint")
      (mk "<leader>db" "require('dap').toggle_breakpoint()" "Toggle breakpoint")
      (mk "<leader>dB" "require('dap').set_breakpoint(vim.fn.input('Breakpoint condition: '))"
        "Conditional breakpoint"
      )
      (mk "<leader>dp" "require('dap').set_breakpoint(nil, nil, vim.fn.input('Log point message: '))"
        "Log point"
      )

      # Inspection. Hover evaluates the expression under the cursor in a float
      # (works in visual mode too, on the selection). Watch adds it to dap-view's
      # persistent Watches section.
      (mk "<leader>de" "require('dap.ui.widgets').hover()" "Eval under cursor")
      (mk "<leader>dw" "require('dap-view').add_expr()" "Watch expression")
      (mk "<leader>dv" "require('dap-view').toggle()" "Toggle debug view")
      (mk "<leader>dj" "require('dap-view').jump_to_view('watches')" "Jump to debug view")
      {
        mode = "v";
        key = "<leader>de";
        action = lib.nixvim.mkRaw "function() require('dap.ui.widgets').hover() end";
        options = {
          silent = true;
          desc = "Eval selection";
        };
      }
    ];
}

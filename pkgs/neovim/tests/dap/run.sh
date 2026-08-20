#!/usr/bin/env bash
# End-to-end DAP demo / regression test.
#
# Proves the full debugging chain works by driving a real, headless debug
# session and reading variable values back out of a stopped Rust binary:
#
#     nvim-dap  ->  codelldb  ->  lldb  ->  compiled demo binary
#
# It compiles demo.rs with debug info, sets a breakpoint inside a loop, launches
# under codelldb, reads the locals at the breakpoint, steps, and confirms the
# values changed. Exits non-zero (and prints FAIL) if any link is broken, so it
# doubles as a regression test after nvim / nixpkgs bumps.
#
# We run the *built* neovim in --clean mode (no user config, so rustaceanvim /
# rust-analyzer are out of the picture) with the plugin pack dir on packpath, so
# nvim-dap loads exactly as it ships in your editor. In the real editor
# rustaceanvim wires this adapter for you; here harness.lua does it by hand for a
# self-contained run.
#
# NOTE: this must be run from an interactive shell / your real environment. Under
# some sandboxes, a headless nvim that spawns a child (codelldb) that inherits
# stdout can wedge the parent's pipe; running it from a normal terminal is fine.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FLAKE="/home/niko/nixos"
BP_LINE=8   # the `acc *= i;` line inside the loop

echo "[1/6] compile demo.rs -g ....................... (building)"

NVIM_STORE="$(nix build "$FLAKE#neovim" --accept-flake-config --no-link --print-out-paths 2>/dev/null)"
NVIM="$NVIM_STORE/bin/nvim"

# Plugin pack dir (holds nvim-dap etc.) from the built nvim's closure.
PACK="$(nix-store -qR "$NVIM_STORE" 2>/dev/null | grep -E 'vim-pack-dir$' | head -1)"
[ -n "$PACK" ] || { echo "FAIL: could not find vim-pack-dir in nvim closure" >&2; exit 1; }

# Compile demo.rs with a real CC-stdenv (rustc alone can't link — it needs a C
# linker, which the devshell-less global env lacks). runCommandCC provides cc.
DEMO_OUT="$(nix build --no-link --print-out-paths --accept-flake-config --impure --expr "
  let pkgs = (builtins.getFlake \"$FLAKE\").inputs.nixpkgs.legacyPackages.\${builtins.currentSystem};
  in pkgs.runCommandCC \"dap-demo\" { } ''
    mkdir -p \$out/bin
    \${pkgs.rustc}/bin/rustc -g -o \$out/bin/demo \${$HERE/demo.rs}
  ''
" 2>/dev/null)"
BIN="$DEMO_OUT/bin/demo"
[ -x "$BIN" ] || { echo "FAIL: demo did not compile" >&2; exit 1; }
echo "   -> compiled: $BIN"

# codelldb on PATH for the session.
CODELLDB="$(nix build --no-link --print-out-paths --accept-flake-config --impure --expr "
  (builtins.getFlake \"$FLAKE\").inputs.nixpkgs.legacyPackages.\${builtins.currentSystem}.vscode-extensions.vadimcn.vscode-lldb.adapter
" 2>/dev/null)"
export PATH="$CODELLDB/bin:$PATH"
command -v codelldb >/dev/null || { echo "FAIL: codelldb not on PATH" >&2; exit 1; }
echo

SRC="$HERE/demo.rs"
"$NVIM" --headless --clean \
  -c "set packpath^=$PACK" \
  -c "lua vim.g.demo_bin='$BIN'; vim.g.demo_src='$SRC'; vim.g.demo_bp_line=$BP_LINE" \
  -c "luafile $HERE/harness.lua"

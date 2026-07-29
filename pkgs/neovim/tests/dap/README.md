# DAP demo / regression test

An end-to-end proof that Rust debugging works in this config. It drives a real,
headless debug session and reads variable values back out of a stopped binary:

```
nvim-dap  ->  codelldb  ->  lldb  ->  compiled demo binary
```

## Run it

```sh
pkgs/neovim/tests/dap/run.sh
```

Run it from a **normal terminal** (not an automated/sandboxed harness): a
headless nvim that spawns codelldb can wedge a captured stdout pipe in some
sandboxes. In an interactive shell it's fine.

Expected output ends with:

```
RESULT: chain verified  nvim-dap -> codelldb -> lldb -> demo binary
```

Non-zero exit + a `FAIL:` line means a link in the chain broke — useful as a
regression check after bumping neovim, nvim-dap, or nixpkgs.

## Files

- `demo.rs`     — tiny `factorial` with a loop; breakpoint lands on `acc *= i;`.
- `harness.lua` — wires the codelldb adapter by hand (in your real editor
  rustaceanvim does this automatically), sets the breakpoint, launches, reads
  locals via the DAP `scopes`/`variables` requests, steps, and asserts the
  values changed.
- `run.sh`      — builds the demo binary (with a CC stdenv, since rustc needs a
  linker), puts codelldb on PATH, and runs the built nvim's plugin set in
  `--clean` mode so nothing but nvim-dap is involved.

## How to actually debug in the editor

This harness is a *proof*; day-to-day you just:

1. Open a Rust file in a cargo project.
2. `<leader>rd` (Rust: debuggables) → pick a target, **or** `<F9>`/`<leader>db`
   to set a breakpoint then `<F5>` to launch.
3. Step with `<F10>` (over) / `<F11>` (into) / `<S-F11>` (out); the debug view
   opens automatically and shows scopes, watches, call stack, and inline
   virtual-text values next to each line. `<leader>de` evaluates the expression
   under the cursor. `<S-F5>` terminates.

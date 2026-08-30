# Rust development environment
# - rustaceanvim (rust-analyzer integration)
# - rustfmt formatting
# - Rust-specific keymaps
{
  lib,
  pkgs,
  rustAnalyzerSettings,
  ...
}:
{
  whichKeyGroups = [
    {
      __unkeyed = "<leader>r";
      group = "Rust";
    }
  ];

  plugins.rustaceanvim = {
    enable = true;

    settings = {
      server = {
        # lspmux client shim, wrapped so that a selected session is attached to
        # by name. `lspmux-attach` re-execs `lspmux client` under `env -i` and
        # points --server-path at the session wrapper, which carries the saved
        # devshell environment internally -- so every editor asking for the same
        # session lands on the same server instance regardless of which terminal
        # it was started from. With no session selected it degrades to a plain
        # `lspmux client` passing the ambient (direnv) environment.
        #
        # Requires: services.lspmux.enable = true in NixOS config.
        # Sessions are created from a devshell with `lspmux-session save NAME`.
        #
        # NOTE: rustaceanvim has its own lspmux support (server.lspmux.enable,
        # on by default when server.cmd is unset) but it is NOT usable here: it
        # connects over TCP and sends `lspMux = {version, method, server}` with
        # no `env` field, so lspmux spawns rust-analyzer from the systemd user
        # service environment and has no way to name a session.
        #
        # Consequence: `:RustAnalyzer target <triple>` does not work. Use
        # `:RustSession` / <leader>rT instead -- see M.switch below. (The builtin
        # is broken upstream anyway: it notifies an already-stopped client and
        # then restarts from a freshly-built config, so the target is dropped.
        # Even if it worked, the `settings` function below would overwrite
        # cargo.target from the session metadata on the next start.)
        cmd = [ "lspmux-attach" ];

        # Shared with opencode's `lsp.rust.initialization` so that whichever
        # client initializes a shared lspmux session proposes the same config.
        # See the header of lib/rust-analyzer-settings.nix.
        default_settings = rustAnalyzerSettings;

        # Called fresh on every RustAnalyzer start. lspmux replays the *first*
        # client's initialize result to everyone that joins an instance, so
        # later clients' settings are discarded -- deriving the target from the
        # session metadata rather than per-editor state is what keeps every
        # client's view consistent with the server that actually got spawned.
        settings = lib.nixvim.mkRaw ''
          function(project_root, default_settings)
            default_settings["rust-analyzer"].cargo.target =
              require('rust-session').current_target(project_root)
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
    formatters_by_ft.rust = [ "rustfmt" ];
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
      key = "<leader>dd";
      action = lib.nixvim.mkRaw ''
        function()
          if vim.bo.filetype ~= "rust" then
            vim.notify("Debug-at-cursor is Rust-only for now", vim.log.levels.WARN)
            return
          end
          vim.cmd.RustLsp('debug')
        end
      '';
      options = {
        silent = true;
        desc = "Rust: Debug target at cursor";
      };
    }
    {
      mode = "n";
      key = "<leader>rT";
      action = lib.nixvim.mkRaw ''
        function()
          require('rust-session').pick()
        end
      '';
      options = {
        silent = true;
        desc = "Rust: Switch lspmux session";
      };
    }
  ];

  extraConfigLua = ''
    do
      local M = {}

      local function sessions_dir()
        -- HOME alone, deliberately ignoring XDG_STATE_HOME: this must agree
        -- byte-for-byte with lspmux-attach, which cannot consult XDG_STATE_HOME
        -- because the opencode sandbox doesn't set it.
        return vim.env.HOME .. "/.local/state/lspmux/sessions"
      end

      --- Repository containing `dir`, resolved. Sessions are keyed per repo, so
      --- every subdirectory has to land on the same answer.
      ---
      --- A linked worktree's ".git" is a *file* pointing at
      --- <main>/.git/worktrees/<name>, not a directory -- vim.fs.root stops at
      --- the worktree itself, which would give every worktree a distinct,
      --- session-less key. Detect that file and resolve through to the main
      --- checkout instead, mirroring repo_root() in pkgs/lspmux-session.
      local function repo_root(dir)
        dir = dir or vim.uv.cwd()
        local root = vim.fs.root(dir, ".git") or dir
        local st = vim.uv.fs_stat(root .. "/.git")
        if st and st.type == "file" then
          local fd = io.open(root .. "/.git", "r")
          if fd then
            local line = fd:read("*l")
            fd:close()
            local gitdir = line and line:match("^gitdir:%s*(.-)%s*$")
            local main = gitdir and gitdir:match("^(.*)/%.git/worktrees/[^/]+$")
            if main then
              root = main
            end
          end
        end
        return vim.uv.fs_realpath(root) or root
      end

      --- Directory holding a repository's sessions, nil if it has none.
      --- Mirrors group_dir() in pkgs/lspmux-session: keyed by inode because that
      --- survives reboots and is identical inside the sandbox, where the path
      --- differs; falling back to the recorded path when the inode has changed.
      local function group_dir(root)
        local st = vim.uv.fs_stat(root)
        if not st then
          return nil
        end
        local base = (root:match("[^/]+$") or "root"):gsub("[^%w._-]", "_")
        -- %d, not tostring: luv hands back a double, and a large inode would
        -- otherwise format as scientific notation.
        local dir = ("%s/%s@%d"):format(sessions_dir(), base, st.ino)
        if vim.fn.isdirectory(dir) == 1 then
          return dir
        end
        if vim.fn.isdirectory(sessions_dir()) == 0 then
          return nil
        end
        for name, kind in vim.fs.dir(sessions_dir()) do
          if kind == "directory" then
            for sub, subkind in vim.fs.dir(sessions_dir() .. "/" .. name) do
              if subkind == "directory" then
                local path = ("%s/%s/%s/meta.json"):format(sessions_dir(), name, sub)
                if vim.fn.filereadable(path) == 1 then
                  local ok, meta = pcall(vim.json.decode, table.concat(vim.fn.readfile(path), "\n"))
                  if ok and type(meta) == "table" and meta.root == root then
                    return sessions_dir() .. "/" .. name
                  end
                end
              end
            end
          end
        end
        return nil
      end

      local function read_meta(group, name)
        local path = group .. "/" .. name .. "/meta.json"
        if vim.fn.filereadable(path) == 0 then
          return nil
        end
        local ok, meta = pcall(function()
          -- luanil: a session with no target records `"target": null`, and the
          -- default decode turns that into vim.NIL -- which is truthy, so it
          -- would sail through `meta.target and ...` checks as a userdata.
          return vim.json.decode(
            table.concat(vim.fn.readfile(path), "\n"),
            { luanil = { object = true, array = true } }
          )
        end)
        if not ok or type(meta) ~= "table" then
          return nil
        end
        return meta
      end

      --- Sessions saved for the repository containing `dir`, sorted by name.
      --- Sessions from other repos are excluded rather than merely unranked:
      --- lspmux keys instances on workspace root as well as server path, so
      --- attaching one would silently spawn a second server with that repo's
      --- environment rather than joining anything.
      function M.for_cwd(dir)
        local group = group_dir(repo_root(dir))
        if not group then
          return {}
        end
        local out = {}
        for name, kind in vim.fs.dir(group) do
          if kind == "directory" then
            local meta = read_meta(group, name)
            if meta then
              table.insert(out, meta)
            end
          end
        end
        table.sort(out, function(a, b)
          return a.name < b.name
        end)
        return out
      end

      --- The session this directory currently resolves to, nil if none.
      --- Same rule as lspmux-attach: most recently selected wins.
      function M.current(dir)
        local best = nil
        for _, meta in ipairs(M.for_cwd(dir)) do
          if not best or (meta.selected_at or 0) > (best.selected_at or 0) then
            best = meta
          end
        end
        return best
      end

      --- cargo target recorded for the active session, nil if none/native.
      function M.current_target(dir)
        local meta = M.current(dir)
        return meta and meta.target or nil
      end

      --- Select a named lspmux session for this repository and restart against it.
      --- The selection is written to the session store rather than held in this
      --- process, so every other editor on the repo -- including opencode in the
      --- sandbox -- follows on its next start instead of needing to be told.
      function M.switch(name)
        if not name or name == "" then
          return M.pick()
        end

        local root = repo_root()
        local prev = M.current()
        prev = prev and prev.name or nil
        if name == prev then
          vim.notify("Already on lspmux session " .. name, vim.log.levels.INFO)
          return
        end

        local function select(session)
          return vim.system(
            { "lspmux-session", "use", session },
            { cwd = root, text = true }
          ):wait()
        end

        local res = select(name)
        if res.code ~= 0 then
          vim.notify(
            "lspmux-session use " .. name .. ": " .. vim.trim(res.stderr or ""),
            vim.log.levels.ERROR
          )
          return
        end

        -- :RustAnalyzer is a *buffer-local* command (created by rustaceanvim's
        -- ftplugin), and focus may move while we wait for the old client to
        -- exit -- so pin the buffer we issue it from.
        local bufnr = vim.api.nvim_get_current_buf()

        local outgoing = vim.lsp.get_clients({ name = "rust-analyzer" })

        -- rust-analyzer serves *pull* diagnostics, which live in a namespace
        -- keyed by client id ("nvim.lsp.rust-analyzer.<id>.<pull_id>"). Neovim
        -- only clears those on LspDetach when no other attached client supports
        -- textDocument/diagnostic -- typos_lsp does, so the outgoing client's
        -- namespace survives and its diagnostics get layered under the new
        -- session's. Match by name to catch both the push ("nvim.lsp.<name>.<id>")
        -- and pull namespaces without having to know the server's pull_id.
        local stale_ns = {}
        for _, client in ipairs(outgoing) do
          local base = ("nvim.lsp.%s.%d"):format(client.name, client.id)
          for id, ns in pairs(vim.diagnostic.get_namespaces()) do
            if ns.name == base or vim.startswith(ns.name, base .. ".") then
              table.insert(stale_ns, id)
            end
          end
        end

        local function start()
          for _, ns in ipairs(stale_ns) do
            vim.diagnostic.reset(ns)
          end
          vim.api.nvim_buf_call(bufnr, function()
            vim.cmd("RustAnalyzer start")
          end)
          local verb = prev and "Switched to" or "Attached to"
          vim.notify(verb .. " lspmux session " .. name, vim.log.levels.INFO)
        end

        -- Stop tears down the lspmux client pipe, start spawns a new one that
        -- re-resolves the repository's selected session -> lspmux-attach points
        -- it at the matching wrapper, so lspmux routes to that instance (or
        -- spawns it, restoring the saved devshell environment).
        vim.api.nvim_buf_call(bufnr, function()
          vim.cmd("RustAnalyzer stop")
        end)

        -- client:stop() is async. Starting on a fixed delay races the shutdown:
        -- if the old client is still alive, vim.lsp.start's default reuse_client
        -- (name + root_dir match) hands it back and the switch silently no-ops.
        -- Poll until every outgoing client has actually exited.
        local attempts = 0
        local max_attempts = 50
        local function wait()
          for _, client in ipairs(outgoing) do
            if not client:is_stopped() then
              attempts = attempts + 1
              if attempts > max_attempts then
                vim.notify(
                  "rust-analyzer did not stop; session not switched",
                  vim.log.levels.ERROR
                )
                if prev then
                  select(prev)
                end
                return
              end
              vim.defer_fn(wait, 100)
              return
            end
          end
          start()
        end
        vim.defer_fn(wait, 100)
      end

      function M.pick()
        local sessions = M.for_cwd()
        if #sessions == 0 then
          vim.notify(
            "No lspmux sessions for this repository.\n"
              .. "Create one from the devshell: lspmux-session save <name>",
            vim.log.levels.WARN
          )
          return
        end

        local current = M.current()
        current = current and current.name or nil

        local items = {}
        for _, meta in ipairs(sessions) do
          table.insert(items, {
            label = meta.name .. (meta.target and (" -- " .. meta.target) or ""),
            name = meta.name,
          })
        end

        vim.ui.select(items, {
          prompt = "lspmux session:",
          format_item = function(item)
            return item.label .. (item.name == current and " ● " or "")
          end,
        }, function(choice)
          if choice then
            M.switch(choice.name)
          end
        end)
      end

      function M.complete(lead)
        local results = {}
        for _, meta in ipairs(M.for_cwd()) do
          if meta.name:find(lead, 1, true) == 1 then
            table.insert(results, meta.name)
          end
        end
        return results
      end

      -- Register module so the keymap can require() it
      package.loaded["rust-session"] = M

      vim.api.nvim_create_user_command("RustSession", function(opts)
        M.switch(opts.args)
      end, {
        nargs = "?",
        complete = function(lead)
          return M.complete(lead)
        end,
        desc = "Switch rust-analyzer to a named lspmux session. No args = picker.",
      })
    end
  '';
}

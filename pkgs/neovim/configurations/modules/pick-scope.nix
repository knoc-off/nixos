# Single source of truth for mini.pick's "working scope" — the directory that
# scoped pickers (<leader>ff/<leader>fg) search from. Resolution ladder:
#   1. per-buffer pin (vim.b.pick_scope)
#   2. global pin (set via <leader>fs — pick a project root from the marker ladder)
#   3. auto: nearest ancestor with a package/workspace marker (Cargo.toml,
#      package.json, flake.nix, ...), tiers are equal priority so e.g. a repo
#      root flake.nix never masks a package-level default.nix
#   4. narrowest attached LSP root_dir
#   5. git root
#   6. cwd
{...}: {
  extraConfigLua = ''
    _G.PickScope = {}
    local Scope = _G.PickScope

    -- Single source of truth for what counts as a "project root" marker, shared
    -- by auto-detection (vim.fs.root) and the <leader>fs ladder picker.
    -- Add markers here to widen both to more ecosystems.
    local MARKER_NAMES = {
      "Cargo.toml", "package.json", "deno.json", "deno.jsonc",
      "pyproject.toml", "setup.py", "setup.cfg", "go.mod", "go.work",
      "flake.nix", "default.nix", "shell.nix", "pom.xml", "build.gradle",
      "build.gradle.kts", "CMakeLists.txt", "meson.build", "Gemfile",
      "composer.json", "mix.exs", "build.zig", ".luarc.json", "stylua.toml",
      "pnpm-workspace.yaml",
    }
    local function is_ext_marker(name)
      return name:match("%.csproj$") ~= nil or name:match("%.fsproj$") ~= nil or name:match("%.cabal$") ~= nil
    end

    -- Set form for O(1) membership in the ladder walk.
    local MARKER_SET = {}
    for _, n in ipairs(MARKER_NAMES) do MARKER_SET[n] = true end

    -- vim.fs.root marker spec. Nested first tier = equal priority; only falls
    -- through to the extension matcher, then '.git', when none is found.
    -- NOTE: vim.fs.find requires each tier to be either all-strings or a single
    -- function, never mixed — so is_ext_marker must be its own tier.
    local MARKERS = { MARKER_NAMES, is_ext_marker, ".git" }

    local function repo_root(bufnr)
      return vim.fs.root(bufnr or 0, ".git")
    end

    local function auto_root(bufnr)
      bufnr = bufnr or 0
      local dir = vim.fs.root(bufnr, MARKERS)
      if dir then return dir end
      -- No marker found anywhere up to (and including) the git root: fall back
      -- to the narrowest attached LSP root_dir, if any.
      local narrowest
      for _, client in ipairs(vim.lsp.get_clients({ bufnr = bufnr })) do
        local rd = client.root_dir
        if rd and (not narrowest or #rd > #narrowest) then narrowest = rd end
      end
      return narrowest or repo_root(bufnr) or vim.fn.getcwd()
    end

    -- Repo root, for display (relativizing labels) and as the floor for `up()`.
    Scope.get_repo_root = function()
      return repo_root(0) or vim.fn.getcwd()
    end

    Scope.get = function()
      if vim.b.pick_scope then return vim.b.pick_scope end
      if Scope._global then return Scope._global end
      return auto_root(0)
    end

    Scope.is_pinned = function()
      return vim.b.pick_scope ~= nil or Scope._global ~= nil
    end

    Scope.set = function(dir, opts)
      opts = opts or {}
      dir = vim.fs.abspath(dir)
      if opts.global then
        Scope._global = dir
        vim.b.pick_scope = nil
      else
        vim.b.pick_scope = dir
      end
    end

    Scope.clear = function()
      vim.b.pick_scope = nil
      Scope._global = nil
    end

    -- Short label for the statusline: nil at repo root (nothing to show),
    -- otherwise the scope dir relative to the repo root.
    Scope.label = function()
      local dir = Scope.get()
      local root = Scope.get_repo_root()
      if dir == root then return nil end
      local rel = dir:sub(#root + 2)
      if rel == "" then rel = vim.fs.basename(dir) end
      return rel
    end

    -- A workspace marker groups multiple sub-packages, so scoping there searches
    -- all members at once (vs a single leaf package). Detect it to disambiguate
    -- the otherwise-identical-looking marker levels in the ladder. Line-anchored
    -- matching is load-bearing: member crates are full of `foo.workspace = true`
    -- but only a real workspace root has a `[workspace]` section header.
    local function file_matches(path, pattern)
      local fh = io.open(path, "r")
      if not fh then return false end
      local n = 0
      for line in fh:lines() do
        n = n + 1
        if n > 400 then break end
        if line:match(pattern) then fh:close(); return true end
      end
      fh:close()
      return false
    end

    -- Annotate a bare marker filename with "(workspace)" when it denotes one.
    -- go.work / pnpm-workspace.yaml are workspaces by existence (no read needed).
    local function annotate(dir, name)
      if name == "go.work" or name == "pnpm-workspace.yaml" then return name .. " (workspace)" end
      if name == "Cargo.toml" and file_matches(dir .. "/" .. name, "^%s*%[workspace") then
        return name .. " (workspace)"
      end
      if name == "package.json" and file_matches(dir .. "/" .. name, '^%s*"workspaces"%s*:') then
        return name .. " (workspace)"
      end
      return name
    end

    -- Walk from the current buffer's directory up to (and including) the nearest
    -- .git, collecting every ancestor that holds a project-root marker. Returns
    -- nearest -> widest, one entry per directory: { dir = <abs>, text = <markers> }.
    Scope.ladder = function(bufnr)
      bufnr = bufnr or 0
      local name = vim.api.nvim_buf_get_name(bufnr)
      local start = (name ~= "" and vim.bo[bufnr].buftype == "")
        and vim.fs.dirname(vim.fs.abspath(name))
        or vim.fn.getcwd()

      local dirs = { start }
      for p in vim.fs.parents(start) do dirs[#dirs + 1] = p end

      local out = {}
      for _, d in ipairs(dirs) do
        local markers, has_git = {}, false
        local ok, it = pcall(vim.fs.dir, d)
        if ok then
          for entry, _ in it do
            if entry == ".git" then
              has_git = true
            elseif MARKER_SET[entry] or is_ext_marker(entry) then
              markers[#markers + 1] = annotate(d, entry)
            end
          end
        end
        table.sort(markers)
        if has_git then markers[#markers + 1] = ".git" end
        if #markers > 0 then out[#out + 1] = { dir = d, text = table.concat(markers, ", ") } end
        if has_git then break end
      end
      return out
    end

    -- <leader>fs: pick a project root from the ladder and pin it globally.
    -- Every option is a real marker directory, so (unlike a free directory
    -- browser) you can't accidentally scope to a meaningless subdir like src/.
    Scope.pick = function()
      local MiniPick = require("mini.pick")
      local entries = Scope.ladder(0)
      if #entries == 0 then
        vim.notify("No project-root markers found above this file", vim.log.levels.WARN)
        return
      end

      local root = Scope.get_repo_root()
      local active = Scope.get()

      -- Aligned display: "<●/ > <rel-dir> │ <markers>". "●" marks the currently
      -- active scope; repo root shows as ".".
      local rel = {}
      local relw = 0
      for i, e in ipairs(entries) do
        local r = e.dir == root and "." or e.dir:sub(#root + 2)
        if r == "" then r = vim.fs.basename(e.dir) end
        rel[i] = r
        relw = math.max(relw, vim.fn.strchars(r))
      end
      local items = {}
      for i, e in ipairs(entries) do
        local mark = e.dir == active and "●" or " "
        local pad = rel[i] .. string.rep(" ", relw - vim.fn.strchars(rel[i]))
        items[i] = { path = e.dir, text = string.format("%s %s │ %s", mark, pad, e.text) }
      end

      MiniPick.start({
        source = {
          items = items,
          name = "Project root (scope)",
          choose = function(item)
            if item == nil then return end
            Scope.set(item.path, { global = true })
            vim.notify("Scope: " .. item.path, vim.log.levels.INFO)
          end,
        },
      })
    end
  '';
}

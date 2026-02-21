# mini.files - file explorer with git status integration
# Reads from GitState (source of truth) for comparison base
# Shows both working tree status AND branch diff (files changed since merge-base)
{lib, ...}: {
  plugins.mini = {
    enable = true;
    modules.files = {
      options.use_as_default_explorer = true;
    };
  };

  # Keymap to open mini.files
  keymaps = [
    {
      mode = "n";
      key = "-";
      action = lib.nixvim.mkRaw ''
        function()
          local MiniFiles = require('mini.files')
          local buf_name = vim.api.nvim_buf_get_name(0)
          local path = vim.fn.filereadable(buf_name) == 1 and buf_name or vim.fn.getcwd()
          MiniFiles.open(path)
          MiniFiles.reveal_cwd()
        end
      '';
      options.desc = "Open file explorer";
    }
  ];

  # Git status integration for mini.files
  # Reads from GitState for comparison base
  extraConfigLua = ''
    local nsMiniFiles = vim.api.nvim_create_namespace("mini_files_git")
    local autocmd = vim.api.nvim_create_autocmd

    -- Cache for git data
    local gitCache = {
      worktree = {},      -- Working tree status (staged/modified/untracked)
      branch = {},        -- Branch diff (files changed since merge-base)
      base = nil,         -- The base used for branch diff
      time = 0,
    }
    local cacheTimeout = 2000

    -- Status types for combined display
    -- W = working tree change, B = branch change, WB = both
    local function getStatusInfo(worktree_status, is_in_branch)
      -- Working tree symbols (uncommitted changes)
      local worktreeMap = {
        [" M"] = { symbol = "●", hl = "GitSignsChange" },  -- Modified
        ["M "] = { symbol = "✓", hl = "GitSignsAdd" },     -- Staged
        ["MM"] = { symbol = "≠", hl = "GitSignsChange" },  -- Both
        ["A "] = { symbol = "+", hl = "GitSignsAdd" },     -- Added
        ["AA"] = { symbol = "≈", hl = "GitSignsAdd" },
        ["D "] = { symbol = "-", hl = "GitSignsDelete" },  -- Deleted
        ["AM"] = { symbol = "⊕", hl = "GitSignsChange" },
        ["AD"] = { symbol = "⊖", hl = "GitSignsChange" },
        ["R "] = { symbol = "→", hl = "GitSignsChange" },  -- Renamed
        ["U "] = { symbol = "‖", hl = "GitSignsChange" },  -- Unmerged
        ["UU"] = { symbol = "⇄", hl = "GitSignsChange" },
        ["UA"] = { symbol = "⊕", hl = "GitSignsAdd" },
        ["??"] = { symbol = "?", hl = "Comment" },         -- Untracked
        ["!!"] = { symbol = "!", hl = "NonText" },         -- Ignored
      }

      local symbol = ""
      local hl = "NonText"

      if worktree_status then
        local info = worktreeMap[worktree_status]
        if info then
          symbol = info.symbol
          hl = info.hl
        end
      end

      -- If file is in branch diff (changed since merge-base)
      if is_in_branch then
        if worktree_status then
          -- Both: branch change + uncommitted changes
          -- Use a distinct color to show it's tracked in branch
          symbol = "◆" .. symbol
          hl = "DiagnosticInfo"  -- Blue-ish to indicate "tracked in branch"
        else
          -- Only in branch diff (committed, no uncommitted changes)
          symbol = "◆"
          hl = "DiagnosticHint"  -- Subtle color for committed-only
        end
      end

      return symbol, hl
    end

    -- Fetch working tree status (git status)
    local function fetchWorktreeStatus(cwd, callback)
      vim.system(
        { "git", "status", "--ignored", "--porcelain" },
        { text = true, cwd = cwd },
        function(result)
          if result.code == 0 then
            callback(result.stdout)
          else
            callback("")
          end
        end
      )
    end

    -- Fetch branch diff (files changed since merge-base)
    local function fetchBranchDiff(cwd, base, callback)
      if not base or base == "HEAD" then
        callback("")
        return
      end

      vim.system(
        { "git", "diff", "--name-only", base .. "...HEAD" },
        { text = true, cwd = cwd },
        function(result)
          if result.code == 0 then
            callback(result.stdout)
          else
            callback("")
          end
        end
      )
    end

    -- Parse git status output into path -> status map
    local function parseWorktreeStatus(content)
      local statusMap = {}
      for line in content:gmatch("[^\r\n]+") do
        local status, filePath = string.match(line, "^(..)%s+(.*)")
        if status and filePath then
          -- Build path hierarchy so directories show status too
          local parts = {}
          for part in filePath:gmatch("[^/]+") do
            table.insert(parts, part)
          end
          local currentKey = ""
          for i, part in ipairs(parts) do
            currentKey = i > 1 and (currentKey .. "/" .. part) or part
            if i == #parts then
              statusMap[currentKey] = status
            elseif not statusMap[currentKey] then
              statusMap[currentKey] = status
            end
          end
        end
      end
      return statusMap
    end

    -- Parse branch diff output into set of paths
    local function parseBranchDiff(content)
      local pathSet = {}
      for line in content:gmatch("[^\r\n]+") do
        if line ~= "" then
          -- Add the file itself
          pathSet[line] = true
          -- Also add parent directories
          local parts = {}
          for part in line:gmatch("[^/]+") do
            table.insert(parts, part)
          end
          local currentKey = ""
          for i, part in ipairs(parts) do
            currentKey = i > 1 and (currentKey .. "/" .. part) or part
            pathSet[currentKey] = true
          end
        end
      end
      return pathSet
    end

    -- Update mini.files buffer with git decorations
    local function updateMiniWithGit(buf_id)
      vim.schedule(function()
        if not vim.api.nvim_buf_is_valid(buf_id) then return end

        local ok, MiniFiles = pcall(require, "mini.files")
        if not ok then return end

        local nlines = vim.api.nvim_buf_line_count(buf_id)
        local cwd = vim.fs.root(buf_id, ".git")
        if not cwd then return end

        local escapedcwd = vim.pesc(vim.fs.normalize(cwd))

        -- Clear existing extmarks
        vim.api.nvim_buf_clear_namespace(buf_id, nsMiniFiles, 0, -1)

        for i = 1, nlines do
          local entry = MiniFiles.get_fs_entry(buf_id, i)
          if not entry then break end

          local relativePath = entry.path:gsub("^" .. escapedcwd .. "/", "")
          local worktree_status = gitCache.worktree[relativePath]
          local is_in_branch = gitCache.branch[relativePath]

          if worktree_status or is_in_branch then
            local symbol, hl = getStatusInfo(worktree_status, is_in_branch)

            if symbol ~= "" then
              -- Sign column indicator
              vim.api.nvim_buf_set_extmark(buf_id, nsMiniFiles, i - 1, 0, {
                sign_text = symbol,
                sign_hl_group = hl,
                priority = 2,
              })

              -- Color the filename
              local line = vim.api.nvim_buf_get_lines(buf_id, i - 1, i, false)[1]
              if line then
                local nameStart = line:find(vim.pesc(entry.name))
                if nameStart then
                  vim.api.nvim_buf_set_extmark(buf_id, nsMiniFiles, i - 1, nameStart - 1, {
                    end_col = nameStart + #entry.name - 1,
                    hl_group = hl,
                  })
                end
              end
            end
          end
        end
      end)
    end

    -- Fetch all git data and update display
    local function refreshGitData(buf_id)
      local cwd = vim.fs.root(buf_id, ".git")
      if not cwd then return end

      local currentTime = os.time()
      local base = _G.GitState and _G.GitState.get_base() or "HEAD"

      -- Check cache validity
      if gitCache.time > 0
         and (currentTime - gitCache.time) < cacheTimeout
         and gitCache.base == base then
        updateMiniWithGit(buf_id)
        return
      end

      -- Fetch both data sources
      local pending = 2
      local function checkDone()
        pending = pending - 1
        if pending == 0 then
          gitCache.time = currentTime
          gitCache.base = base
          updateMiniWithGit(buf_id)
        end
      end

      -- Fetch working tree status
      fetchWorktreeStatus(cwd, function(content)
        gitCache.worktree = parseWorktreeStatus(content)
        checkDone()
      end)

      -- Fetch branch diff (only if we have a base that's not HEAD)
      if base and base ~= "HEAD" then
        fetchBranchDiff(cwd, base, function(content)
          gitCache.branch = parseBranchDiff(content)
          checkDone()
        end)
      else
        gitCache.branch = {}
        checkDone()
      end
    end

    -- Clear cache
    local function clearCache()
      gitCache = {
        worktree = {},
        branch = {},
        base = nil,
        time = 0,
      }
    end

    -- Expose for external integration
    _G.MiniFilesGitInvalidate = clearCache

    local augroup = vim.api.nvim_create_augroup("MiniFilesGit", { clear = true })

    -- Refresh on explorer open
    autocmd("User", {
      group = augroup,
      pattern = "MiniFilesExplorerOpen",
      callback = function()
        refreshGitData(vim.api.nvim_get_current_buf())
      end,
    })

    -- Clear cache on close
    autocmd("User", {
      group = augroup,
      pattern = "MiniFilesExplorerClose",
      callback = clearCache,
    })

    -- Refresh on buffer navigation
    autocmd("User", {
      group = augroup,
      pattern = "MiniFilesBufferUpdate",
      callback = function(args)
        if gitCache.time > 0 then
          updateMiniWithGit(args.data.buf_id)
        end
      end,
    })

    -- Listen for GitState changes (from git.nix keymaps)
    autocmd("User", {
      group = augroup,
      pattern = "GitStateBaseChanged",
      callback = function()
        clearCache()
        -- If mini.files is open, refresh it
        local ok, MiniFiles = pcall(require, "mini.files")
        if ok then
          local buf_id = vim.api.nvim_get_current_buf()
          local ft = vim.bo[buf_id].filetype
          if ft == "minifiles" then
            refreshGitData(buf_id)
          end
        end
      end,
    })

    -- Listen for GitState invalidation
    autocmd("User", {
      group = augroup,
      pattern = "GitStateInvalidate",
      callback = clearCache,
    })
  '';
}

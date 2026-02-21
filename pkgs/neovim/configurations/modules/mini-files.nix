# mini.files - file explorer with git status integration
# Uses gitsigns highlight groups for consistency
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
  extraConfigLua = ''
    -- mini.files git status integration
    -- Based on https://gist.github.com/bassamsdata/eec0a3065152226581f8d4244cce9051
    local nsMiniFiles = vim.api.nvim_create_namespace("mini_files_git")
    local autocmd = vim.api.nvim_create_autocmd

    -- Cache for git status
    local gitStatusCache = {}
    local cacheTimeout = 2000

    local function mapSymbols(status)
      -- Using GitSigns highlight groups for consistency
      local statusMap = {
        [" M"] = { symbol = "●", hl = "GitSignsChange" },  -- Modified in working dir
        ["M "] = { symbol = "✓", hl = "GitSignsChange" },  -- Staged modification
        ["MM"] = { symbol = "≠", hl = "GitSignsChange" },  -- Modified in both
        ["A "] = { symbol = "+", hl = "GitSignsAdd" },     -- Staged new file
        ["AA"] = { symbol = "≈", hl = "GitSignsAdd" },     -- Added in both
        ["D "] = { symbol = "-", hl = "GitSignsDelete" },  -- Staged deletion
        ["AM"] = { symbol = "⊕", hl = "GitSignsChange" },  -- Added, then modified
        ["AD"] = { symbol = "⊖", hl = "GitSignsChange" },  -- Added, then deleted
        ["R "] = { symbol = "→", hl = "GitSignsChange" },  -- Renamed
        ["U "] = { symbol = "‖", hl = "GitSignsChange" },  -- Unmerged
        ["UU"] = { symbol = "⇄", hl = "GitSignsChange" },  -- Both modified (conflict)
        ["UA"] = { symbol = "⊕", hl = "GitSignsAdd" },     -- Unmerged, added
        ["??"] = { symbol = "?", hl = "Comment" },         -- Untracked
        ["!!"] = { symbol = "!", hl = "NonText" },         -- Ignored
      }
      local result = statusMap[status] or { symbol = "?", hl = "NonText" }
      return result.symbol, result.hl
    end

    local function fetchGitStatus(cwd, callback)
      vim.system(
        { "git", "status", "--ignored", "--porcelain" },
        { text = true, cwd = cwd },
        function(result)
          if result.code == 0 then
            callback(result.stdout)
          end
        end
      )
    end

    local function parseGitStatus(content)
      local gitStatusMap = {}
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
              gitStatusMap[currentKey] = status
            elseif not gitStatusMap[currentKey] then
              gitStatusMap[currentKey] = status
            end
          end
        end
      end
      return gitStatusMap
    end

    local function updateMiniWithGit(buf_id, gitStatusMap)
      vim.schedule(function()
        -- Guard: ensure buffer is still valid
        if not vim.api.nvim_buf_is_valid(buf_id) then return end

        local ok, MiniFiles = pcall(require, "mini.files")
        if not ok then return end

        local nlines = vim.api.nvim_buf_line_count(buf_id)
        local cwd = vim.fs.root(buf_id, ".git")
        if not cwd then return end

        local escapedcwd = vim.pesc(vim.fs.normalize(cwd))

        for i = 1, nlines do
          local entry = MiniFiles.get_fs_entry(buf_id, i)
          if not entry then break end

          local relativePath = entry.path:gsub("^" .. escapedcwd .. "/", "")
          local status = gitStatusMap[relativePath]

          if status then
            local symbol, hl = mapSymbols(status)
            -- Sign column indicator
            vim.api.nvim_buf_set_extmark(buf_id, nsMiniFiles, i - 1, 0, {
              sign_text = symbol,
              sign_hl_group = hl,
              priority = 2,
            })
            -- Color the filename
            local line = vim.api.nvim_buf_get_lines(buf_id, i - 1, i, false)[1]
            local nameStart = line:find(vim.pesc(entry.name))
            if nameStart then
              vim.api.nvim_buf_set_extmark(buf_id, nsMiniFiles, i - 1, nameStart - 1, {
                end_col = nameStart + #entry.name - 1,
                hl_group = hl,
              })
            end
          end
        end
      end)
    end

    local function updateGitStatus(buf_id)
      local cwd = vim.fs.root(buf_id, ".git")
      if not cwd then return end

      local currentTime = os.time()
      if gitStatusCache[cwd] and currentTime - gitStatusCache[cwd].time < cacheTimeout then
        updateMiniWithGit(buf_id, gitStatusCache[cwd].statusMap)
      else
        fetchGitStatus(cwd, function(content)
          local gitStatusMap = parseGitStatus(content)
          gitStatusCache[cwd] = { time = currentTime, statusMap = gitStatusMap }
          updateMiniWithGit(buf_id, gitStatusCache[cwd].statusMap)
        end)
      end
    end

    local function clearCache()
      gitStatusCache = {}
    end

    local augroup = vim.api.nvim_create_augroup("MiniFilesGit", { clear = true })

    autocmd("User", {
      group = augroup,
      pattern = "MiniFilesExplorerOpen",
      callback = function()
        updateGitStatus(vim.api.nvim_get_current_buf())
      end,
    })

    autocmd("User", {
      group = augroup,
      pattern = "MiniFilesExplorerClose",
      callback = clearCache,
    })

    autocmd("User", {
      group = augroup,
      pattern = "MiniFilesBufferUpdate",
      callback = function(args)
        local cwd = vim.fs.root(args.data.buf_id, ".git")
        if gitStatusCache[cwd] then
          updateMiniWithGit(args.data.buf_id, gitStatusCache[cwd].statusMap)
        end
      end,
    })
  '';
}

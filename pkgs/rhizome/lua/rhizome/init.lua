--- rhizome.nvim -- Trilium notes as Neovim buffers.
---
--- The Lua side is deliberately thin. All conversion, verification and splicing
--- happens in the `rhizome` binary, which speaks LSP; this module owns buffers,
--- commands and the picker. Completion, hover, diagnostics and goto-definition
--- are handled by Neovim's built-in LSP client and need no code here.

local M = {}

local dates = require("rhizome.date")

local state = {
  ---@type table<integer, { note_id: string, blob_id: string, read_only: boolean }>
  buffers = {},
  --- Reverse of `buffers`, so a second `M.open` for a note already open
  --- (via a link, the picker, note-graph navigation, ...) reuses that buffer
  --- instead of creating another one. Needed because the buffer's *name*
  --- carries the note's title (see `M.open`) and is not itself a stable key:
  --- it changes on rename, and `vim.fn.bufadd` only matches by exact name.
  ---@type table<string, integer>
  note_bufnr = {},
  opts = {},
  client_id = nil,
  --- Requests in flight. `:w` stays fire-and-forget for responsiveness, but
  --- quitting needs to know when it is safe to let the process exit.
  pending = 0,
}

local defaults = {
  --- Path to the rhizome binary.
  bin = "rhizome",
  --- Trilium server root, e.g. "https://trilium.example.com".
  url = nil,
  --- Environment variable to read the URL from when `url` is unset.
  url_env = "RHIZOME_URL",
  --- ETAPI token. Prefer `token_env` so it never sits in your config.
  token = nil,
  --- Shell command printing the token on stdout.
  token_cmd = nil,
  --- Environment variable holding the token. This is the seam that keeps the
  --- editor config free of any particular secret manager: whatever populates
  --- the environment (sops, direnv, a password manager) is none of its
  --- business.
  token_env = "RHIZOME_TOKEN",
  --- Fold opaque HTML fences on open.
  fold_opaque = true,
  --- Render `[[noteId|Title]]` links with their live title instead of
  --- whatever text is stored in the link (which Trilium itself ignores).
  link_titles = true,
  --- Where a note opens when the triggering command carries no explicit
  --- `:split`/`:vsplit`/`:tab` modifier of its own: "current" (switch the
  --- current window's buffer -- the note becomes a listed buffer, so it
  --- shows up as its own entry in bufferline/tabline; this is the default),
  --- "tab" (a real new tabpage), "vsplit", or "split". An explicit modifier
  --- on the command always wins over this. Ignored if the note is already
  --- open in a visible window -- that window is focused instead, rather
  --- than opening a second view of it.
  open_mode = "current",
}

local function notify(message, level)
  vim.notify("rhizome: " .. message, level or vim.log.levels.INFO)
end

function M.resolve_token()
  if state.opts.token then
    return state.opts.token
  end
  if state.opts.token_cmd then
    local out = vim.fn.system(state.opts.token_cmd)
    if vim.v.shell_error ~= 0 then
      error("token_cmd failed: " .. out)
    end
    return vim.trim(out)
  end
  local value = vim.env[state.opts.token_env or defaults.token_env]
  -- An unset variable and one set to "" are the same mistake from here.
  if value == nil or value == "" then
    return nil
  end
  return vim.trim(value)
end

function M.resolve_url()
  return state.opts.url or vim.env[state.opts.url_env or defaults.url_env]
end

function M.resolve_bin()
  return state.opts.bin or defaults.bin
end

--- Which variables the health check should tell you to set.
function M.token_env()
  return state.opts.token_env or defaults.token_env
end

function M.url_env()
  return state.opts.url_env or defaults.url_env
end

--- Neovim renamed the client request method; support both call styles.
local function request(client, method, params, handler, bufnr)
  state.pending = state.pending + 1
  local function done(...)
    state.pending = math.max(0, state.pending - 1)
    if handler then
      handler(...)
    end
  end
  if vim.fn.has("nvim-0.11") == 1 then
    return client:request(method, params, done, bufnr)
  end
  return client.request(method, params, done, bufnr)
end

--- Like `request`, but blocks until the reply arrives (or `timeout_ms` elapses).
--- Used where async would race something observable: quitting the editor,
--- or a `BufReadCmd` that a preview window is about to render.
local function request_sync(client, method, params, bufnr, timeout_ms)
  local response
  request(client, method, params, function(err, result)
    response = { err = err, result = result }
  end, bufnr)
  local ok = vim.wait(timeout_ms or 10000, function()
    return response ~= nil
  end, 20)
  if not ok then
    return { message = "timed out waiting for rhizome" }, nil
  end
  return response.err, response.result
end

--- `textDocument/definition`-style params for the cursor in the current
--- window, against `uri` rather than the buffer's own -- `uri_from_bufnr`
--- would try to file-path-encode a `trilium-meta://` buffer name, which the
--- server's `canonical_uri` doesn't parse back out. The position itself
--- (UTF-16 columns, not the bytes `nvim_win_get_cursor` deals in) is exactly
--- what `vim.lsp.util.make_position_params` already gets right; the second
--- `pcall` only exists for Neovim versions old enough to reject the explicit
--- `offset_encoding` argument.
local function position_params(uri)
  local ok, params = pcall(vim.lsp.util.make_position_params, 0, "utf-16")
  if not ok then
    params = vim.lsp.util.make_position_params()
  end
  params.textDocument = { uri = uri }
  return params
end

local function client_config()
  local url = M.resolve_url()
  if not url then
    error(("no server url configured (set opts.url or $%s)"):format(
      state.opts.url_env or defaults.url_env
    ))
  end
  local token = M.resolve_token()
  if not token then
    error(("no ETAPI token configured (set opts.token_cmd or $%s)"):format(
      state.opts.token_env or defaults.token_env
    ))
  end
  return {
    name = "rhizome",
    cmd = { state.opts.bin, "lsp" },
    cmd_env = { RHIZOME_URL = url, RHIZOME_TOKEN = token },
    root_dir = vim.uv.cwd(),
    -- Fired once, when the background fetch that `serve` kicks off at
    -- startup lands (or fails). Not fired for `:Rhizome reindex`, which
    -- reports its own result synchronously since it is a deliberate,
    -- already-waited-for action rather than something happening in the
    -- background.
    handlers = {
      ["rhizome/indexStatus"] = function(_, result)
        if result.ok then
          notify(("indexed %d notes"):format(result.count))
        else
          notify("background index refresh failed: " .. tostring(result.error), vim.log.levels.WARN)
        end
      end,
    },
    -- `@today` completion never creates anything just by being browsed: the
    -- item's textEdit only deletes the typed "@keyword", and this handler
    -- (run after that edit lands) is what actually resolves the date note and
    -- inserts the link. That split exists because Trilium's calendar
    -- endpoint creates the day note as a side effect of reading it.
    commands = {
      ["rhizome.dateLink"] = function(command, ctx)
        local keyword = command.arguments and command.arguments[1] and command.arguments[1].keyword
        if not keyword then
          return
        end
        M.insert_date_link(keyword, ctx.bufnr)
      end,
      ["rhizome.createFromLink"] = function(command, ctx)
        local arg = command.arguments and command.arguments[1]
        if not arg then
          return
        end
        M.create_from_link(arg.oldNoteId, arg.title, ctx.bufnr)
      end,
      ["rhizome.searchNotes"] = function(_, ctx)
        M.insert_link_from_index(ctx.bufnr)
      end,
      ["rhizome.convertToList"] = function(command, ctx)
        local arg = command.arguments and command.arguments[1]
        if not arg then
          return
        end
        M.convert_metadata_to_list(arg.line, arg.name, arg.value, ctx.bufnr)
      end,
      ["rhizome.createFromMetadataValue"] = function(command, ctx)
        local arg = command.arguments and command.arguments[1]
        if not arg then
          return
        end
        M.create_from_metadata_value(arg.value, arg.line, ctx.bufnr)
      end,
      ["rhizome.simplifyLink"] = function(command, ctx)
        local arg = command.arguments and command.arguments[1]
        if not arg then
          return
        end
        M.simplify_link(arg.path, arg.noteId, ctx.bufnr)
      end,
    },
  }
end

--- Resolve (and, via Trilium's calendar endpoint, get-or-create) the day note
--- for `keyword` and insert a reference link at the cursor.
function M.insert_date_link(keyword, bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local date = dates.keyword(keyword)
  if not date then
    notify("unknown date keyword '" .. keyword .. "'", vim.log.levels.ERROR)
    return
  end
  local client = vim.lsp.get_client_by_id(state.client_id)
  if not client then
    notify("backend is not running", vim.log.levels.ERROR)
    return
  end
  request(client, "rhizome/dateNote", { date = date }, function(err, result)
    if err then
      notify(err.message or vim.inspect(err), vim.log.levels.ERROR)
      return
    end
    local link = ("[[%s|%s]]"):format(result.noteId, result.title)
    local row, col = unpack(vim.api.nvim_win_get_cursor(0))
    vim.api.nvim_buf_set_text(bufnr, row - 1, col, row - 1, col, { link })
    vim.api.nvim_win_set_cursor(0, { row, col + #link })
  end, bufnr)
end

--- Start (or reuse) the backend and attach it to `bufnr`.
local function attach(bufnr)
  local id = vim.lsp.start(client_config(), { bufnr = bufnr })
  if not id then
    error("could not start '" .. state.opts.bin .. "'")
  end
  state.client_id = id
  return vim.lsp.get_client_by_id(id)
end

--- Fold the `=html` fences that carry opaque blocks.
--- Exposed because 'foldexpr' needs a global-reachable function.
function M.foldexpr(lnum)
  local line = vim.fn.getline(lnum)
  if line:match("^`+=html") then
    return "a1"
  end
  if line:match("^`+$") then
    return "s1"
  end
  return "="
end

--- `includeexpr` for `gf` on a `[[noteId|Title]]`.
---
--- `v:fname` is useless here: `isfname` extraction is word-oriented and knows
--- nothing about link syntax, so with the cursor on the title half of
--- `[[JEppDgkHmgUf|David Selby]]` it yields `David`, and on ordinary prose it
--- yields whatever word the cursor sits on. Prefixing either with `trilium://`
--- sent `gf` off to fetch a note by that name, which 404s -- and no pattern on
--- the string alone can tell a note id from an English word. So the link is
--- found by scanning the current line directly (`rhizome.links` already does
--- this to place virtual titles), and `v:fname` is returned untouched for
--- anything that is not a link, where normal `gf` behavior is what's wanted.
function M.includeexpr(fname)
  local ok, cursor = pcall(vim.api.nvim_win_get_cursor, 0)
  if ok then
    local link = require("rhizome.links").link_at(vim.api.nvim_get_current_line(), cursor[2])
    if link then
      -- `target`, not `note_id`: the link may be written as a full
      -- notePath, and only the resolved note is fetchable.
      return "trilium://" .. link.target
    end
  end
  return fname
end

local DIRTY_SIGN_GROUP = "rhizome-dirty"
vim.fn.sign_define("RhizomeDirty", { text = "~", texthl = "DiffChange" })

--- Mark the lines `rhizome/save` would actually rewrite, so unsaved edits are
--- visible per-block rather than as one buffer-wide "modified" flag.
--- Debounced on a timer rather than every keystroke, since it costs a
--- round-trip through the same block matcher the save path uses.
local dirty_timer = {}
--- Bumped by every refresh and by `M.save`, and captured by each in-flight
--- `rhizome/dirty` request. A reply only applies its signs if the epoch it
--- was sent under is still current -- otherwise it is describing a buffer
--- state that a save (or a newer edit) has already superseded, and applying
--- it would resurrect signs for text that no longer exists. Without this, a
--- request fired just before `:w` and answered just after it would redraw
--- the exact "~" marks the save was supposed to clear.
local dirty_epoch = {}
local function refresh_dirty_signs(bufnr)
  local entry = state.buffers[bufnr]
  local client = vim.lsp.get_client_by_id(state.client_id)
  if not entry or not client or entry.read_only then
    return
  end
  if dirty_timer[bufnr] then
    dirty_timer[bufnr]:stop()
  end
  dirty_epoch[bufnr] = (dirty_epoch[bufnr] or 0) + 1
  local epoch = dirty_epoch[bufnr]
  dirty_timer[bufnr] = vim.defer_fn(function()
    if not vim.api.nvim_buf_is_valid(bufnr) then
      return
    end
    request(client, "rhizome/dirty", { uri = "trilium://" .. entry.note_id }, function(err, result)
      if err or dirty_epoch[bufnr] ~= epoch or not vim.api.nvim_buf_is_valid(bufnr) then
        return
      end
      vim.fn.sign_unplace(DIRTY_SIGN_GROUP, { buffer = bufnr })
      for _, span in ipairs(result.lines or {}) do
        for line = span.start, span["end"] do
          vim.fn.sign_place(0, DIRTY_SIGN_GROUP, "RhizomeDirty", bufnr, { lnum = line + 1 })
        end
      end
    end, bufnr)
  end, 300)
end

--- `conceallevel`/`concealcursor`/`foldmethod` are window-local, not
--- buffer-local -- setting them once at buffer-construction time either
--- errors outright (`vim.bo[buf].conceallevel = ...` rejects window-local
--- options) or silently vanishes (`nvim_buf_call` + `vim.wo.foldmethod` sets
--- it on a throwaway autocmd window when the buffer has no real one yet,
--- which is exactly the state a buffer is in inside `BufReadCmd`). Applying
--- these on every window that currently shows the buffer, and again on
--- `BufWinEnter` for windows opened later (`:split`, a `:pedit` preview),
--- is the only place they reliably stick.
local function apply_window_options(bufnr, read_only)
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_buf(win) == bufnr then
      if state.opts.fold_opaque then
        vim.wo[win].foldmethod = "expr"
        -- The server knows exactly where every fence starts and ends
        -- (`textDocument/foldingRange`); fall back to the hand-rolled regex
        -- only on Neovim versions that predate `vim.lsp.foldexpr`.
        vim.wo[win].foldexpr = vim.lsp.foldexpr and "v:lua.vim.lsp.foldexpr()"
          or "v:lua.require'rhizome'.foldexpr(v:lnum)"
      end
      if state.opts.link_titles and not read_only then
        vim.wo[win].conceallevel = 2
        -- Never auto-reveal on cursor position: concealed text and the
        -- inline virt_text replacing it render *both* at once when Vim's own
        -- `concealcursor` reveal kicks in. Revealing raw text under the
        -- cursor is `rhizome.links`' job, done synchronously so it never
        -- flashes back to raw before the title catches up.
        vim.wo[win].concealcursor = "nvic"
      end
    end
  end
end

local function configure_buffer(bufnr, read_only)
  vim.bo[bufnr].filetype = "markdown"
  vim.bo[bufnr].buftype = "acwrite"
  vim.bo[bufnr].swapfile = false
  vim.bo[bufnr].modifiable = not read_only
  -- `bufadd` (used to create this buffer -- see `M.open`) never lists it, so
  -- without this a note would load and edit fine but never show up as its
  -- own tab in a bufferline/tabline running in "buffers" mode -- it would
  -- structurally not exist as far as that mode's buffer list is concerned.
  vim.bo[bufnr].buflisted = true
  -- `gf` on a `[[noteId|Title]]` under the cursor -- see `M.includeexpr` for
  -- why this can't just trust the filename Vim hands it.
  vim.bo[bufnr].includeexpr = "v:lua.require'rhizome'.includeexpr(v:fname)"

  apply_window_options(bufnr, read_only)
  vim.api.nvim_create_autocmd("BufWinEnter", {
    group = vim.api.nvim_create_augroup("rhizome-winopts-" .. bufnr, { clear = true }),
    buffer = bufnr,
    callback = function()
      apply_window_options(bufnr, read_only)
    end,
  })

  if not read_only then
    vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
      group = vim.api.nvim_create_augroup("rhizome-dirty-" .. bufnr, { clear = true }),
      buffer = bufnr,
      callback = function()
        refresh_dirty_signs(bufnr)
      end,
    })
  end
end

local function set_lines(bufnr, text)
  local modifiable = vim.bo[bufnr].modifiable
  vim.bo[bufnr].modifiable = true
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, vim.split(text, "\n", { plain = true }))
  vim.bo[bufnr].modified = false
  vim.bo[bufnr].modifiable = modifiable
end

--- True when `mods` (a `:command` modifier table, e.g. from `smods`) asks
--- for a specific window placement. `smods` always has all ~19 fields
--- present with zero-value defaults (`split = ""`, `tab = -1`, ...), so
--- `next(mods) ~= nil` is true even for a bare `:Rhizome today` -- checking
--- for a truthy field is the only way to tell "no modifier" from "one was
--- given".
local function wants_split(mods)
  return mods ~= nil
    and (mods.split ~= "" or mods.vertical or mods.horizontal or (mods.tab and mods.tab >= 0))
end

--- The `trilium://<id>` scheme optionally carries a `/<title>` suffix purely
--- for display -- see `M.open`. The id is the only part that means anything;
--- this is the one place that gets to assume otherwise.
local function note_id_from_uri(uri)
  return uri:match("^trilium://([^/]+)")
end

--- ASCII substitute for characters that would either be eaten by `:t` (a
--- literal `/`) or corrupt the buffer name (control characters).
---
--- Kept in lockstep with `sanitize_title` in `crates/rhizomed/src/lsp/mod.rs`:
--- the same title has to sanitize to the same string on both sides, or a note
--- opened directly and the same note reached through a link end up as two
--- different buffer names for one note.
local function sanitize_title(title)
  if not title or title == "" then
    return "untitled"
  end
  return (title:gsub("[/\n\r\t]", "-"))
end

--- The window already showing `bufnr`, in any tab, or nil.
local function window_showing(bufnr)
  for _, win in ipairs(vim.fn.win_findbuf(bufnr)) do
    if vim.api.nvim_win_is_valid(win) then
      return win
    end
  end
  return nil
end

--- Reopening a note already visible somewhere jumps to that window rather
--- than opening a second view of it -- `nvim_set_current_win` switches
--- tabpages on its own when the target window lives in a different one, so
--- this covers both "already in this tab" and "open in another tab".
---
--- Otherwise, an explicit `:split`/`:vsplit`/`:tab` modifier on the
--- triggering command always wins; absent one, `state.opts.open_mode`
--- decides where a note lands, defaulting to a new tab so that opening a
--- note never silently overwrites whatever the current window was already
--- showing.
local function place_window(bufnr, mods)
  local existing_win = window_showing(bufnr)
  if existing_win then
    vim.api.nvim_set_current_win(existing_win)
    return
  end

  if wants_split(mods) then
    vim.cmd({ cmd = "sbuffer", args = { bufnr }, mods = mods })
    return
  end

  local mode = state.opts.open_mode
  if mode == "tab" then
    vim.cmd({ cmd = "sbuffer", args = { bufnr }, mods = { tab = vim.fn.tabpagenr() } })
  elseif mode == "vsplit" then
    vim.cmd({ cmd = "sbuffer", args = { bufnr }, mods = { vertical = true } })
  elseif mode == "split" then
    vim.cmd({ cmd = "sbuffer", args = { bufnr } })
  else
    vim.api.nvim_win_set_buf(0, bufnr)
  end
end

--- Open a note by id, in a buffer named `trilium://<noteId>/<title>` once its
--- title is known (bare `trilium://<noteId>` until then).
---@param note_id string
---@param opts? { focus?: boolean, sync?: boolean, mods?: table, scratch_buf?: integer }
function M.open(note_id, opts)
  opts = opts or {}

  -- The buffer's name carries its title (set below, once fetched), so it is
  -- not a stable key: `vim.fn.bufadd` only matches by exact name, and would
  -- create a second buffer for a note already open under its titled name.
  -- `note_bufnr` is the actual identity.
  local existing = state.note_bufnr[note_id]
  if existing and vim.api.nvim_buf_is_valid(existing) then
    if opts.scratch_buf and opts.scratch_buf ~= existing then
      -- A preview window (quickfix, `:pedit`, Neovim's own definition jump)
      -- already created and is about to show `scratch_buf` -- a fresh, empty
      -- buffer, because whatever built its target URI did not know this
      -- note was already open. This runs *inside* `vim.fn.bufload`, called
      -- from Neovim's own `vim.lsp.util.get_lines` (in turn called from
      -- `locations_to_items`, which builds preview text for every jump
      -- target before any window is touched) -- so `scratch_buf` is still
      -- in use by that caller and must not be torn down synchronously here.
      -- `bufhidden = "wipe"` lets Neovim reclaim it on its own once nothing
      -- shows it any more, and the redirect itself is deferred a tick so it
      -- runs after that caller has finished reading from it.
      vim.bo[opts.scratch_buf].bufhidden = "wipe"
      local scratch_buf = opts.scratch_buf
      vim.schedule(function()
        if not vim.api.nvim_buf_is_valid(scratch_buf) then
          return
        end
        for _, win in ipairs(vim.fn.win_findbuf(scratch_buf)) do
          if vim.api.nvim_win_is_valid(win) then
            vim.api.nvim_win_set_buf(win, existing)
          end
        end
      end)
      return
    end
    if opts.focus ~= false then
      place_window(existing, opts.mods)
    end
    return
  end

  -- `scratch_buf`, when given, is a buffer Neovim's own LSP machinery
  -- already created for a jump target (see `BufReadCmd` below) -- fetch
  -- straight into it rather than creating a second buffer under a bare
  -- name, which would collide with it once this one is renamed to the same
  -- titled name below.
  local bufnr = opts.scratch_buf
  if not bufnr then
    bufnr = vim.fn.bufadd("trilium://" .. note_id)

    -- `bufload` on a not-yet-read buffer fires `BufReadCmd`, whose handler
    -- (below) calls back into `M.open` itself to do the actual fetch. If
    -- that happens, this call must not repeat the fetch: doing so doubles
    -- every request and doubles the "N blocks, M raw HTML" notification.
    local was_loaded = vim.fn.bufloaded(bufnr) == 1
    vim.fn.bufload(bufnr)
    if not was_loaded and state.buffers[bufnr] then
      if opts.focus ~= false then
        place_window(bufnr, opts.mods)
      end
      return
    end
  end

  local ok, client = pcall(attach, bufnr)
  if not ok then
    notify(tostring(client), vim.log.levels.ERROR)
    return
  end

  local function place(result)
    configure_buffer(bufnr, result.readOnly)
    set_lines(bufnr, result.buffer)
    state.buffers[bufnr] = {
      note_id = result.noteId,
      blob_id = result.blobId,
      read_only = result.readOnly,
    }
    state.note_bufnr[result.noteId] = bufnr
    vim.api.nvim_buf_set_name(bufnr, "trilium://" .. result.noteId .. "/" .. sanitize_title(result.title))
    if opts.focus ~= false then
      place_window(bufnr, opts.mods)
    end

    if state.opts.link_titles and not result.readOnly then
      require("rhizome.links").attach(bufnr, client)
    end
    if not result.readOnly then
      vim.fn.sign_unplace(DIRTY_SIGN_GROUP, { buffer = bufnr })
    end

    if result.readOnly then
      notify(("%s -- %s note, read-only"):format(result.title, result.noteType))
    elseif result.stats and result.stats ~= vim.NIL then
      notify(("%s -- %d blocks, %d raw HTML"):format(
        result.title,
        result.stats.total,
        result.stats.opaque
      ))
    else
      notify(("%s -- %s"):format(result.title, result.mime))
    end
  end

  if opts.sync then
    -- A preview window (quickfix, BufReadCmd) renders the buffer the moment
    -- this call returns, so the fetch cannot be left to a callback.
    local err, result = request_sync(client, "rhizome/open", { noteId = note_id }, bufnr)
    if err then
      notify(err.message or vim.inspect(err), vim.log.levels.ERROR)
      -- Nothing will ever be read into this buffer now. It cannot be wiped
      -- synchronously -- a preview window may still be about to show it --
      -- so mark it for reclaim once nothing does, the same as the redirect
      -- above.
      vim.bo[bufnr].bufhidden = "wipe"
      return
    end
    place(result)
    return
  end

  request(client, "rhizome/open", { noteId = note_id }, function(err, result)
    if err then
      notify(err.message or vim.inspect(err), vim.log.levels.ERROR)
      vim.bo[bufnr].bufhidden = "wipe"
      return
    end
    place(result)
  end, bufnr)
end

--- Write the buffer back to Trilium.
---@param bufnr integer
---@param force? boolean
---@param sync? boolean Block until Trilium confirms. Used when quitting, since
---   a fire-and-forget save can lose data if the process exits before the
---   reply arrives.
function M.save(bufnr, force, sync)
  local entry = state.buffers[bufnr]
  if not entry then
    notify("buffer is not a Trilium note", vim.log.levels.ERROR)
    return
  end
  if entry.read_only then
    notify("this note type is read-only", vim.log.levels.WARN)
    return
  end
  local client = vim.lsp.get_client_by_id(state.client_id)
  if not client then
    notify("backend is not running", vim.log.levels.ERROR)
    return
  end

  local text = table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), "\n")
  local params = {
    uri = "trilium://" .. entry.note_id,
    text = text,
    force = force or false,
  }

  local function handle(err, result)
    if err then
      notify("save failed: " .. (err.message or vim.inspect(err)), vim.log.levels.ERROR)
      return
    end
    if result.conflict then
      -- ETAPI cannot reject a stale write, so the decision has to be the
      -- user's rather than silently going either way.
      local choice = vim.fn.confirm(
        "This note changed in Trilium since it was opened.\nOverwrite those changes?",
        "&Overwrite\n&Cancel",
        2
      )
      if choice == 1 then
        M.save(bufnr, true, sync)
      end
      return
    end
    entry.blob_id = result.blobId
    if dirty_timer[bufnr] then
      dirty_timer[bufnr]:stop()
    end
    dirty_epoch[bufnr] = (dirty_epoch[bufnr] or 0) + 1
    set_lines(bufnr, result.buffer)
    vim.fn.sign_unplace(DIRTY_SIGN_GROUP, { buffer = bufnr })
    notify("saved")
  end

  if sync then
    local err, result = request_sync(client, "rhizome/save", params, bufnr, 15000)
    handle(err, result)
    return
  end
  request(client, "rhizome/save", params, handle, bufnr)
end

--- The running client, or a freshly attached one on a scratch buffer if
--- nothing is open yet. Used by anything that needs to talk to the server
--- without requiring a Trilium buffer to already be focused.
local function any_client()
  local client = vim.lsp.get_client_by_id(state.client_id)
  if client then
    return client
  end
  local scratch = vim.api.nvim_create_buf(false, true)
  local ok, started = pcall(attach, scratch)
  if not ok then
    notify(tostring(started), vim.log.levels.ERROR)
    return nil
  end
  return started
end

--- Fire a `rhizome/*` request against `note_id` regardless of which buffer
--- (if any) is current -- unlike `metadata_request` below, which is always
--- the *current* buffer's note. The browse picker's mutation verbs routinely
--- act on a note other than the one open in the active window.
local function mutate(method, note_id, params, on_done)
  local client = any_client()
  if not client then
    return
  end
  params = vim.tbl_extend("force", { noteId = note_id }, params or {})
  request(client, method, params, function(err, result)
    if err then
      notify(err.message or vim.inspect(err), vim.log.levels.ERROR)
      return
    end
    if on_done then
      on_done(result)
    end
  end)
end

--- Keep an already-open buffer for `note_id` in sync with a title changed
--- elsewhere (rename, or any mutation that returns a fresh title) -- the
--- buffer may not be the current one, so this cannot go through `M.rename`'s
--- own bufnr-bound path.
local function sync_open_buffer(note_id, title)
  local bufnr = state.note_bufnr[note_id]
  if not (bufnr and vim.api.nvim_buf_is_valid(bufnr)) then
    return
  end
  if state.buffers[bufnr] then
    state.buffers[bufnr].title = title
  end
  vim.api.nvim_buf_set_name(bufnr, "trilium://" .. note_id .. "/" .. sanitize_title(title))
end

--- Wipe an open buffer for a note that no longer exists (deleted). The usual
--- `BufWipeout` autocmd (see `M.setup`) still runs and clears `state.buffers`/
--- `state.note_bufnr` itself -- this only has to trigger it.
local function close_open_buffer(note_id)
  local bufnr = state.note_bufnr[note_id]
  if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
    vim.api.nvim_buf_delete(bufnr, { force = true })
  end
end

--- `rhizome/search` returns one of two shapes depending on which branch of
--- the server's index-first-with-fallback answered: a local-index match
--- carries `path` (the note's ancestor titles, no type/mime), a live-search
--- match carries `noteType` instead (no path). Picker item text uses
--- whichever is present.
local function display_text(note)
  if note.path and #note.path > 0 then
    return table.concat(note.path, " > ") .. " > " .. note.title
  elseif note.noteType then
    return ("%s  (%s)"):format(note.title, note.noteType)
  else
    return note.title
  end
end

--- `mini.pick` if it's installed and available to `require`, else `nil`.
local function mini_pick()
  local ok, pick = pcall(require, "mini.pick")
  return ok and pick or nil
end

--- `mini.pick` if available, else `vim.ui.select`. Every picker in this
--- module (open a note, insert a link, insert a link from the full local
--- index) is the same shape: a flat list of `{ text, ... }` items and a
--- callback for whichever one gets chosen. `mini.pick` closes its window
--- before running `choose`, so the callback is deferred a tick to land in
--- the window the user is left looking at.
---
--- `extra.mappings` (a `mini.pick` `mappings` table -- see `:h
--- MiniPick-actions`) is silently ignored under `vim.ui.select`, which has
--- no notion of a keymap bound to the item under the cursor; callers that
--- rely on one (`browse`'s `<C-a>` action menu) must also offer an ordinary
--- item that does the same thing, so both front-ends stay usable.
local function pick_one(name, items, choose, extra)
  extra = extra or {}
  local pick = mini_pick()
  if pick then
    pick.start({
      source = {
        items = items,
        name = name,
        choose = function(item)
          vim.schedule(function()
            choose(item)
          end)
        end,
      },
      mappings = extra.mappings,
    })
  else
    vim.ui.select(items, {
      prompt = name,
      format_item = function(item)
        return item.text
      end,
    }, function(item)
      if item then
        choose(item)
      end
    end)
  end
end

--- Search notes and open the chosen one. An empty query browses the entire
--- local index -- `mini.pick`'s own live fuzzy filter narrows it
--- interactively, with no per-keystroke round trip -- while a typed query is
--- narrowed server-side first (see `rhizome/search`'s index-first-with-fallback
--- search).
function M.pick(query, mods)
  local client = any_client()
  if not client then
    return
  end

  if query == "" or query == nil then
    request(client, "rhizome/notes", {}, function(err, notes)
      if err then
        notify("index unavailable: " .. (err.message or vim.inspect(err)), vim.log.levels.ERROR)
        return
      end
      if not notes or #notes == 0 then
        notify("no notes indexed yet -- try :Rhizome reindex")
        return
      end
      local items = {}
      for _, note in ipairs(notes) do
        table.insert(items, {
          text = display_text({ title = note.title, path = note.path }),
          note_id = note.noteId,
        })
      end
      pick_one("Trilium notes", items, function(item)
        M.open(item.note_id, { mods = mods })
      end)
    end)
    return
  end

  request(client, "rhizome/search", { query = query, limit = 200 }, function(err, results)
    if err then
      notify("search failed: " .. (err.message or vim.inspect(err)), vim.log.levels.ERROR)
      return
    end
    if not results or #results == 0 then
      notify("no notes matched")
      return
    end

    local items = {}
    for _, note in ipairs(results) do
      table.insert(items, {
        text = display_text(note),
        note_id = note.noteId,
      })
    end

    pick_one("Trilium notes", items, function(item)
      M.open(item.note_id, { mods = mods })
    end)
  end)
end

--- `:Rhizome browse`: walk the note hierarchy one level at a time instead of
--- `pick`'s flat search. `stack` is the trail of `{ note_id, title }` drilled
--- into so far (root when empty/omitted) -- kept client-side and passed back
--- in on every recursive call, rather than asking the server for "the
--- parent", because that question has no single answer for a note cloned
--- into several parents; this way `..` always retraces the path taken in,
--- never jumps to some canonical location.
---
--- `opts.show_archived` reveals notes carrying `#archived`, hidden by
--- default (matching Trilium's own tree) behind a "show archived" item
--- rather than a separate toggle command.
---
--- `opts.choose_container = { verb, on_choose }` turns browse into a
--- destination picker: drilling in still works the same way, but every
--- level offers "<verb> here" instead of "open"/"+ new note", and choosing
--- any child always drills into it (there is no note to open, only a
--- container to descend into or land on). `on_choose(note_id)` fires once
--- and the picker session ends there -- see `M.pick_destination`.
local function pop_stack(stack)
  local popped = {}
  for i = 1, #stack - 1 do
    popped[i] = stack[i]
  end
  return popped
end

local function push_stack(stack, note_id, title)
  local pushed = {}
  for i = 1, #stack do
    pushed[i] = stack[i]
  end
  pushed[#pushed + 1] = { note_id = note_id, title = title }
  return pushed
end

function M.browse(stack, mods, opts)
  stack = stack or {}
  opts = opts or {}
  local container = opts.choose_container
  local client = any_client()
  if not client then
    return
  end

  local here = stack[#stack]
  request(client, "rhizome/children", { noteId = here and here.note_id or "root" }, function(err, result)
    if err then
      notify("browse failed: " .. (err.message or vim.inspect(err)), vim.log.levels.ERROR)
      return
    end
    local all_children = (result and result.children) or {}
    if #all_children == 0 and not here and not container then
      notify("no notes indexed yet -- try :Rhizome reindex")
      return
    end

    local archived_count = 0
    local children = {}
    for _, child in ipairs(all_children) do
      if child.archived then
        archived_count = archived_count + 1
      end
      if not child.archived or opts.show_archived then
        table.insert(children, child)
      end
    end

    local items = {}
    if here then
      if container then
        table.insert(items, { text = ("-> %s here ('%s')"):format(container.verb, here.title), kind = "choose" })
      else
        table.insert(items, { text = ".  open '" .. here.title .. "'", kind = "open" })
      end
      local up = stack[#stack - 1]
      table.insert(items, { text = "..  up to " .. (up and ("'" .. up.title .. "'") or "root"), kind = "up" })
    elseif container then
      table.insert(items, { text = "->  choose root", kind = "choose", note_id = "root" })
    else
      table.insert(items, { text = "+  new top-level note", kind = "new_root" })
    end
    if archived_count > 0 and not opts.show_archived then
      table.insert(
        items,
        { text = ("(%d archived hidden -- select to show)"):format(archived_count), kind = "show_archived" }
      )
    end
    for _, child in ipairs(children) do
      local suffix = ""
      if child.childCount and child.childCount > 0 then
        suffix = suffix .. ("  (%d)"):format(child.childCount)
      end
      if child.cloneCount and child.cloneCount > 1 then
        suffix = suffix .. "  (clone)"
      end
      if child.archived then
        suffix = suffix .. "  (archived)"
      end
      table.insert(items, {
        text = child.title .. suffix,
        kind = "child",
        note_id = child.noteId,
        title = child.title,
        has_children = (child.childCount or 0) > 0,
      })
    end
    --- Fallback only for `vim.ui.select`, which has no keymaps at all --
    --- under `mini.pick`, `<C-a>` covers the exact same ground (on a child
    --- row or on `.` itself) without a permanent extra row in the list.
    if not container and not mini_pick() and (here or #children > 0) then
      table.insert(items, { text = "?  act on a note...", kind = "actions_menu" })
    end

    --- `<C-a>` under `mini.pick`: act on whichever row the cursor is on --
    --- a child, or `.` itself (the note currently being browsed) -- without
    --- leaving the picker to type a command. Only wired outside
    --- `choose_container` mode (a destination picker has nothing to act
    --- on). Acting on `.` computes the parent/stack one level up, since
    --- that level is what a rename/move/delete invalidates and what
    --- `refresh` should land back on.
    local mappings = nil
    if not container then
      mappings = {
        act_on_note = {
          char = "<C-a>",
          func = function()
            local pick = mini_pick()
            if not pick then
              return
            end
            local matches = pick.get_picker_matches()
            local current = matches and matches.current
            if not current then
              return
            end
            local note_id, title, parent_note_id, target_stack
            if current.kind == "child" then
              note_id, title = current.note_id, current.title
              parent_note_id, target_stack = here and here.note_id or "root", stack
            elseif current.kind == "open" and here then
              local popped = pop_stack(stack)
              note_id, title = here.note_id, here.title
              parent_note_id, target_stack = popped[#popped] and popped[#popped].note_id or "root", popped
            else
              return
            end
            -- `true` tells mini.pick itself to stop (see `:h
            -- MiniPick-actions`); deferring the actual submenu a tick, the
            -- same way `pick_one`'s own `choose` does, lands it in the
            -- window mini.pick leaves behind rather than racing its own
            -- close.
            vim.schedule(function()
              M.note_action_menu(note_id, title, parent_note_id, target_stack, mods, opts)
            end)
            return true
          end,
        },
      }
    end

    pick_one(here and here.title or "Trilium notes", items, function(item)
      if item.kind == "up" then
        M.browse(pop_stack(stack), mods, opts)
      elseif item.kind == "open" then
        M.open(here.note_id, { mods = mods })
      elseif item.kind == "new_root" then
        local title = vim.fn.input({ prompt = "New note title: " })
        if title ~= "" then
          M.create_note(title, "root", mods)
        end
      elseif item.kind == "show_archived" then
        M.browse(stack, mods, vim.tbl_extend("force", opts, { show_archived = true }))
      elseif item.kind == "choose" then
        container.on_choose(item.note_id or here.note_id)
      elseif item.kind == "actions_menu" then
        local action_items = {}
        if here then
          table.insert(
            action_items,
            { text = ".  " .. here.title, note_id = here.note_id, title = here.title, is_here = true }
          )
        end
        for _, child in ipairs(children) do
          table.insert(action_items, { text = child.title, note_id = child.noteId, title = child.title })
        end
        pick_one("act on which note?", action_items, function(picked)
          if picked.is_here then
            local popped = pop_stack(stack)
            local parent_id = popped[#popped] and popped[#popped].note_id or "root"
            M.note_action_menu(picked.note_id, picked.title, parent_id, popped, mods, opts)
          else
            M.note_action_menu(picked.note_id, picked.title, here and here.note_id or "root", stack, mods, opts)
          end
        end)
      else
        local pushed = push_stack(stack, item.note_id, item.title)
        if container or item.has_children then
          M.browse(pushed, mods, opts)
        else
          M.open(item.note_id, { mods = mods })
        end
      end
    end, { mappings = mappings })
  end)
end

--- `:Rhizome browse .`: drill straight into `note_id`'s own children, with
--- the stack seeded from its ancestor trail (see `rhizome/children`'s
--- `trail`) so `..` still retraces the real path upward from here, rather
--- than jumping to root the way starting a fresh `M.browse({})` would.
function M.browse_at(note_id, mods)
  local client = any_client()
  if not client then
    return
  end
  request(client, "rhizome/children", { noteId = note_id }, function(err, result)
    if err then
      notify("browse failed: " .. (err.message or vim.inspect(err)), vim.log.levels.ERROR)
      return
    end
    local stack = {}
    for _, t in ipairs(result.trail or {}) do
      table.insert(stack, { note_id = t.noteId, title = t.title })
    end
    table.insert(stack, { note_id = note_id, title = result.title or note_id })
    M.browse(stack, mods)
  end)
end

--- `:Rhizome browse ..`: `note_id`'s siblings -- browse starting one level
--- up, found the same way (its own ancestor trail, whose last entry is its
--- parent).
function M.browse_up(note_id, mods)
  local client = any_client()
  if not client then
    return
  end
  request(client, "rhizome/children", { noteId = note_id }, function(err, result)
    if err then
      notify("browse failed: " .. (err.message or vim.inspect(err)), vim.log.levels.ERROR)
      return
    end
    local stack = {}
    for _, t in ipairs(result.trail or {}) do
      table.insert(stack, { note_id = t.noteId, title = t.title })
    end
    M.browse(stack, mods)
  end)
end

--- Let the user drill down to a destination note via `browse` itself
--- (`opts.choose_container`), then hand its id to `on_choose`. The single
--- entry point behind both "move to..."/"clone to..." in the action menu
--- and the buffer-bound `:Rhizome move`/`:Rhizome clone` commands.
function M.pick_destination(verb, on_choose)
  M.browse({}, {}, {
    choose_container = { verb = verb, on_choose = on_choose },
  })
end

--- Resolve which of `note_id`'s parents an action should act relative to:
--- straight through if there is only one, otherwise a picker, since a
--- cloned note's placements are not ordered and none is "the" parent.
--- `on_done` is the sole continuation -- nothing is asked at all if
--- `note_id` has no known parent (e.g. the index has never been warmed).
local function pick_parent(note_id, on_choose)
  local client = any_client()
  if not client then
    return
  end
  request(client, "rhizome/parents", { noteId = note_id }, function(err, result)
    if err then
      notify(err.message or vim.inspect(err), vim.log.levels.ERROR)
      return
    end
    local parents = (result and result.parents) or {}
    if #parents == 0 then
      notify("no known parent for this note -- try :Rhizome reindex")
      return
    end
    if #parents == 1 then
      on_choose(parents[1].noteId)
      return
    end
    local items = {}
    for _, parent in ipairs(parents) do
      table.insert(items, { text = parent.title, note_id = parent.noteId })
    end
    pick_one("which parent?", items, function(item)
      on_choose(item.note_id)
    end)
  end)
end

--- Attach `#archived`, idempotently on the server side. `on_done` is only
--- ever called on success -- an error already notified is not also treated
--- as "done".
function M.archive_note(note_id, on_done)
  mutate("rhizome/archive", note_id, {}, function(result)
    notify("archived '" .. result.title .. "'")
    if on_done then
      on_done()
    end
  end)
end

--- Remove `#archived`, idempotently.
function M.unarchive_note(note_id, on_done)
  mutate("rhizome/unarchive", note_id, {}, function(result)
    notify("unarchived '" .. result.title .. "'")
    if on_done then
      on_done()
    end
  end)
end

--- Rename an arbitrary note (not necessarily the current buffer's, unlike
--- `M.rename`) and keep an already-open buffer for it in sync.
function M.rename_note(note_id, new_title, on_done)
  mutate("rhizome/rename", note_id, { title = new_title }, function(result)
    sync_open_buffer(note_id, result.title)
    require("rhizome.links").invalidate()
    notify("renamed to " .. result.title)
    if on_done then
      on_done()
    end
  end)
end

--- Place `note_id` under `to_parent_id` as an additional branch -- the raw
--- mutation, once a destination is already known. See `M.clone_note` for
--- the interactive form that picks one.
function M.clone_note_to(note_id, to_parent_id, on_done)
  mutate("rhizome/clone", note_id, { parentNoteId = to_parent_id }, function(result)
    notify("cloned '" .. result.title .. "'")
    if on_done then
      on_done()
    end
  end)
end

--- `:Rhizome clone`: pick a destination via `browse`, then clone there.
function M.clone_note(note_id, on_done)
  M.pick_destination("clone", function(target_id)
    M.clone_note_to(note_id, target_id, on_done)
  end)
end

--- Move `note_id` from `from_parent_id` to `to_parent_id` -- the raw
--- mutation, once both ends are already known. See `M.move_note` for the
--- interactive form that resolves and picks them.
function M.move_note_to(note_id, from_parent_id, to_parent_id, on_done)
  mutate(
    "rhizome/move",
    note_id,
    { fromParentNoteId = from_parent_id, toParentNoteId = to_parent_id },
    function(result)
      notify("moved '" .. result.title .. "'")
      if on_done then
        on_done()
      end
    end
  )
end

--- `:Rhizome move`: disambiguate which parent to move from (only asks if
--- `note_id` is a clone with more than one), then pick a destination via
--- `browse`.
function M.move_note(note_id, on_done)
  pick_parent(note_id, function(from_parent_id)
    M.pick_destination("move", function(target_id)
      M.move_note_to(note_id, from_parent_id, target_id, on_done)
    end)
  end)
end

--- Remove `note_id` from `parent_id` without touching its other placements
--- -- the raw mutation. See `M.unlink_note` for the interactive form.
function M.unlink_note_from(note_id, parent_id, on_done)
  mutate("rhizome/unlink", note_id, { parentNoteId = parent_id }, function(result)
    notify("unlinked '" .. result.title .. "'")
    if on_done then
      on_done()
    end
  end)
end

--- `:Rhizome unlink`: disambiguate which parent to unlink from, same as
--- `M.move_note`. The server refuses when this would be the note's last
--- parent (it would silently delete the note instead) rather than this
--- side trying to detect that first -- see `rhizome/unlink`.
function M.unlink_note(note_id, on_done)
  pick_parent(note_id, function(parent_id)
    M.unlink_note_from(note_id, parent_id, on_done)
  end)
end

--- `:Rhizome delete`: remove `note_id` everywhere (every branch/clone at
--- once). Soft on Trilium's side and does not prompt -- see
--- `rhizome/delete`.
function M.delete_note(note_id, on_done)
  mutate("rhizome/delete", note_id, {}, function()
    close_open_buffer(note_id)
    notify("deleted")
    if on_done then
      on_done()
    end
  end)
end

--- The `<C-a>`/"act on a note..." submenu inside `browse`: every mutation
--- verb in one place, all built on the same primitives the buffer-bound
--- `:Rhizome` commands use. `parent_note_id` and `stack` are always already
--- known here (browse just drilled through them), so move/clone/unlink skip
--- the disambiguation `M.move_note`/`M.unlink_note` would otherwise need to
--- do, and `refresh` re-enters browse at the same level on success so the
--- list reflects the change immediately. `opts` is the `browse_opts` (e.g.
--- `show_archived`) the caller was displaying, threaded through `refresh` so
--- acting on a note doesn't silently re-hide what was shown.
function M.note_action_menu(note_id, title, parent_note_id, stack, mods, opts)
  local function refresh()
    M.browse(stack, mods, opts)
  end
  local verbs = {
    { text = "new child note...", kind = "new" },
    { text = "rename", kind = "rename" },
    { text = "move to...", kind = "move" },
    { text = "clone to...", kind = "clone" },
    { text = "unlink from here", kind = "unlink" },
    { text = "delete everywhere", kind = "delete" },
    { text = "archive", kind = "archive" },
    { text = "unarchive", kind = "unarchive" },
  }
  pick_one(title, verbs, function(item)
    if item.kind == "new" then
      local new_title = vim.fn.input({ prompt = "New note title: " })
      if new_title ~= "" then
        M.create_note(new_title, note_id, mods)
      end
    elseif item.kind == "rename" then
      local new_title = vim.fn.input({ prompt = "Rename to: ", default = title })
      if new_title ~= "" and new_title ~= title then
        M.rename_note(note_id, new_title, refresh)
      end
    elseif item.kind == "move" then
      M.pick_destination("move", function(target_id)
        M.move_note_to(note_id, parent_note_id, target_id, refresh)
      end)
    elseif item.kind == "clone" then
      M.pick_destination("clone", function(target_id)
        M.clone_note_to(note_id, target_id, refresh)
      end)
    elseif item.kind == "unlink" then
      M.unlink_note_from(note_id, parent_note_id, refresh)
    elseif item.kind == "delete" then
      M.delete_note(note_id, refresh)
    elseif item.kind == "archive" then
      M.archive_note(note_id, refresh)
    elseif item.kind == "unarchive" then
      M.unarchive_note(note_id, refresh)
    end
  end)
end

--- Open the day note for `keyword` ("today", "yesterday", "tomorrow") or a
--- literal `YYYY-MM-DD`.
function M.open_date_note(keyword, mods)
  local date = dates.keyword(keyword) or keyword
  local client = any_client()
  if not client then
    return
  end
  request(client, "rhizome/dateNote", { date = date }, function(err, result)
    if err then
      notify(err.message or vim.inspect(err), vim.log.levels.ERROR)
      return
    end
    M.open(result.noteId, { mods = mods })
  end)
end

function M.open_inbox(mods)
  local date = dates.today()
  local client = any_client()
  if not client then
    return
  end
  request(client, "rhizome/inbox", { date = date }, function(err, result)
    if err then
      notify(err.message or vim.inspect(err), vim.log.levels.ERROR)
      return
    end
    M.open(result.noteId, { mods = mods })
  end)
end

--- Create a note under `parent_note_id` (the current note if unset, else the
--- day's inbox) and open it.
function M.create_note(title, parent_note_id, mods)
  if title == "" then
    notify("new note needs a title: :Rhizome new <title>", vim.log.levels.ERROR)
    return
  end
  local client = any_client()
  if not client then
    return
  end

  local function do_create(parent)
    request(client, "rhizome/create", { parentNoteId = parent, title = title, type = "text" }, function(err, result)
      if err then
        notify(err.message or vim.inspect(err), vim.log.levels.ERROR)
        return
      end
      M.open(result.noteId, { mods = mods })
    end)
  end

  if parent_note_id then
    do_create(parent_note_id)
    return
  end
  local date = dates.today()
  request(client, "rhizome/inbox", { date = date }, function(err, result)
    if err then
      notify(err.message or vim.inspect(err), vim.log.levels.ERROR)
      return
    end
    do_create(result.noteId)
  end)
end

--- Code action on a broken `[[oldId|Title]]`: create a new note with that
--- title and repoint every occurrence of the old id, in this buffer, at it.
--- The new note gets a fresh id from Trilium rather than reusing `oldId`,
--- since ETAPI create-note does not let a caller choose one.
function M.create_from_link(old_id, title, bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local client = any_client()
  if not client then
    return
  end
  local date = dates.today()
  request(client, "rhizome/inbox", { date = date }, function(err, inbox)
    if err then
      notify(err.message or vim.inspect(err), vim.log.levels.ERROR)
      return
    end
    request(client, "rhizome/create", { parentNoteId = inbox.noteId, title = title, type = "text" }, function(err2, created)
      if err2 then
        notify(err2.message or vim.inspect(err2), vim.log.levels.ERROR)
        return
      end
      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      local pattern = vim.pesc(old_id)
      for i, line in ipairs(lines) do
        lines[i] = line:gsub("%[%[" .. pattern .. "([|%]])", "[[" .. created.noteId .. "%1")
      end
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
      notify("created '" .. created.title .. "' and linked it")
    end)
  end)
end

--- Code action on `[[a/b/c|Title]]`: rewrite every occurrence of that exact
--- notePath, in this buffer, down to `[[c|Title]]`. Opt-in rather than
--- automatic -- a notePath is not actually broken, just a form Trilium
--- itself also writes, so this is a tidy-up the user asks for rather than a
--- fix rhizome imposes.
function M.simplify_link(path, note_id, bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local pattern = vim.pesc(path)
  for i, line in ipairs(lines) do
    lines[i] = line:gsub("%[%[" .. pattern .. "([|%]])", "[[" .. note_id .. "%1")
  end
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
end

--- Code action in the metadata pop-out: rewrite a bare `name: value` line
--- into `name:` plus a one-item `- value` list, so a second value can be
--- added without hand-restructuring the YAML. `name`/`value` come from the
--- server's own parse of that exact line (`textDocument/codeAction` ->
--- `convertible_value_at`), not re-derived here, so this can never
--- disagree with what the server saw.
function M.convert_metadata_to_list(line, name, value, bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  vim.api.nvim_buf_set_lines(bufnr, line, line + 1, false, {
    ("  %s:"):format(name),
    ("    - %s"):format(value),
  })
end

--- Code action on a metadata relation value that doesn't resolve to a note:
--- create one titled `value` and replace `value` with its new id, on the
--- line the action was raised on. Unlike `create_from_link`, a metadata
--- value has no `[[...]]` delimiters to bound the replacement, so it is
--- scoped to that single line rather than a buffer-wide substitution.
function M.create_from_metadata_value(value, line, bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local client = any_client()
  if not client then
    return
  end
  local date = dates.today()
  request(client, "rhizome/inbox", { date = date }, function(err, inbox)
    if err then
      notify(err.message or vim.inspect(err), vim.log.levels.ERROR)
      return
    end
    request(client, "rhizome/create", { parentNoteId = inbox.noteId, title = value, type = "text" }, function(err2, created)
      if err2 then
        notify(err2.message or vim.inspect(err2), vim.log.levels.ERROR)
        return
      end
      local text = vim.api.nvim_buf_get_lines(bufnr, line, line + 1, false)[1]
      if not text then
        notify("created '" .. created.title .. "' but its line moved -- edit the buffer manually", vim.log.levels.WARN)
        return
      end
      local replaced, count = text:gsub(vim.pesc(value), created.noteId, 1)
      if count == 0 then
        notify("created '" .. created.title .. "' but its line moved -- edit the buffer manually", vim.log.levels.WARN)
        return
      end
      vim.api.nvim_buf_set_lines(bufnr, line, line + 1, false, { replaced })
      notify("created '" .. created.title .. "' and linked it")
    end)
  end)
end

--- Insert a link to a note picked from search, at the cursor.
function M.insert_link(query)
  local client = any_client()
  if not client then
    return
  end
  request(client, "rhizome/search", { query = query, limit = 200 }, function(err, results)
    if err then
      notify("search failed: " .. (err.message or vim.inspect(err)), vim.log.levels.ERROR)
      return
    end
    if not results or #results == 0 then
      notify("no notes matched")
      return
    end
    local items = {}
    for _, note in ipairs(results) do
      table.insert(items, { text = display_text(note), note = note })
    end

    pick_one("Link a note", items, function(item)
      local link = ("[[%s|%s]]"):format(item.note.noteId, item.note.title)
      local row, col = unpack(vim.api.nvim_win_get_cursor(0))
      vim.api.nvim_buf_set_text(0, row - 1, col, row - 1, col, { link })
      vim.api.nvim_win_set_cursor(0, { row, col + #link })
    end)
  end)
end

--- Multi-token path search over the local note index ("work proj alpha" ->
--- Work > Projects > Alpha), for cases the inline `[[` menu can't reach.
--- blink.cmp closes its completion popup on a space -- its keyword set has
--- no concept of one -- so a query of more than one token can only be typed
--- into a picker's own prompt, never into the buffer itself. Reached either
--- directly (`:Rhizome notes`) or via the "Search all notes..." item at the
--- bottom of the `[[` completion menu (`rhizome.searchNotes`, registered as
--- a client command below).
---@param bufnr? integer
function M.insert_link_from_index(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local client = any_client()
  if not client then
    return
  end
  request(client, "rhizome/notes", {}, function(err, notes)
    if err then
      notify("index unavailable: " .. (err.message or vim.inspect(err)), vim.log.levels.ERROR)
      return
    end
    if not notes or #notes == 0 then
      notify("no notes indexed yet -- try :Rhizome reindex")
      return
    end
    local items = {}
    for _, note in ipairs(notes) do
      local breadcrumb = #note.path > 0 and (table.concat(note.path, " > ") .. " > ") or ""
      table.insert(items, {
        text = breadcrumb .. note.title,
        note_id = note.noteId,
        title = note.title,
      })
    end

    pick_one("All notes", items, function(item)
      local link = ("[[%s|%s]]"):format(item.note_id, item.title)
      local row, col = unpack(vim.api.nvim_win_get_cursor(0))
      vim.api.nvim_buf_set_text(bufnr, row - 1, col, row - 1, col, { link })
      vim.api.nvim_win_set_cursor(0, { row, col + #link })
    end)
  end)
end

--- Force a full refresh of the local note index behind `insert_link_from_index`
--- and the "Search all notes..." completion item.
function M.reindex()
  local client = any_client()
  if not client then
    return
  end
  request(client, "rhizome/reindex", {}, function(err, result)
    if err then
      notify("reindex failed: " .. (err.message or vim.inspect(err)), vim.log.levels.ERROR)
      return
    end
    notify(("reindexed %d notes"):format(result.count))
  end)
end

--- Resolve the note the user means: the current buffer, if it holds one.
local function current_note(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local tracked = state.buffers[bufnr]
  if not tracked then
    notify("not a Trilium buffer", vim.log.levels.ERROR)
    return nil
  end
  local client = vim.lsp.get_client_by_id(state.client_id)
  if not client then
    notify("no connection to the server", vim.log.levels.ERROR)
    return nil
  end
  return tracked.note_id, client, bufnr
end

--- Read-only accessor for `actions.lua`, which lives outside this module's
--- closure and has no other way to see which buffer holds which note.
function M._buffer(bufnr)
  return state.buffers[bufnr]
end

--- Exposed for `links.lua`, which needs to issue its own LSP requests but has
--- no other way to reach the counted/async-aware `request` wrapper.
M._request = request

--- Metadata lives outside the buffer text, so it is edited through the
--- `:Rhizome meta` pop-out. Splicing it inline would put lines in the buffer
--- with no corresponding block in the note, which is exactly what the
--- byte-identity guarantee rests on not happening.
local function metadata_request(method, params, on_done)
  local note_id, client, bufnr = current_note()
  if not note_id then
    return
  end
  params = vim.tbl_extend("force", { noteId = note_id }, params or {})
  request(client, method, params, function(err, result)
    if err then
      notify(err.message or vim.inspect(err), vim.log.levels.ERROR)
      return
    end
    on_done(result, bufnr)
  end, bufnr)
end

function M.rename(title)
  metadata_request("rhizome/rename", { title = title }, function(result, bufnr)
    if state.buffers[bufnr] then
      state.buffers[bufnr].title = result.title
    end
    if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
      vim.api.nvim_buf_set_name(bufnr, "trilium://" .. result.noteId .. "/" .. sanitize_title(result.title))
    end
    -- Any open buffer may hold a `[[thisNoteId|old title]]` link; its cached
    -- display title is now stale.
    require("rhizome.links").invalidate()
    notify("renamed to " .. result.title)
  end)
end

--- Appends a schema section (`rhizome/metadataSchema`'s `labels` or
--- `relations` array) to `lines`: names with a `label:`/`relation:`
--- definition first, each with its `promoted, single, type` detail, then
--- every other name seen anywhere in the vault with no detail at all --
--- same split `metadata_completion` ranks by, just listed instead of
--- filtered against what's being typed.
local function append_schema_section(lines, heading, items)
  if #items == 0 then
    return
  end
  local defined, other = {}, {}
  for _, item in ipairs(items) do
    table.insert(item.defined and defined or other, item)
  end
  table.insert(lines, "")
  table.insert(lines, heading .. " defined for this note")
  if #defined == 0 then
    table.insert(lines, "  (none)")
  else
    for _, item in ipairs(defined) do
      table.insert(lines, ("  %-12s %s"):format(item.name, item.detail))
    end
  end
  if #other > 0 then
    local names = {}
    for _, item in ipairs(other) do
      table.insert(names, item.name)
    end
    table.insert(lines, ("Other %s in this vault: %s"):format(heading:lower(), table.concat(names, ", ")))
  end
end

--- `g?` in the metadata pop-out: a second float over the keymap and syntax
--- reference, plus (once `rhizome/metadataSchema` answers) what this
--- specific note's labels and relations actually are. The syntax half needs
--- no round trip and is shown immediately; the schema half is appended if
--- and when the request comes back, rather than delaying the float on it.
local function metadata_help(client, note_id, parent_buf)
  local lines = {
    "Keys",
    "  :w         apply changes to Trilium",
    "  q          close",
    "  K          explain a name, or preview a relation's target",
    "  gf / gd    jump to the note a relation points at",
    "",
    "Syntax",
    "  labels:",
    "    todo:                          name with no value",
    "    priority: 3                    value (always a string, never coerced)",
    "    genre:                         a name repeated for multiple values",
    "      - sci-fi",
    "      - cyberpunk",
    "    shared: {value: x, inheritable: true}",
    "",
    "  relations:",
    "    template: abc123               value is a noteId",
  }

  local function show(extra)
    if extra then
      vim.list_extend(lines, extra)
    end
    local help_buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(help_buf, 0, -1, false, lines)
    vim.bo[help_buf].modifiable = false
    vim.bo[help_buf].bufhidden = "wipe"
    local width = 0
    for _, line in ipairs(lines) do
      width = math.max(width, #line)
    end
    vim.api.nvim_open_win(help_buf, true, {
      relative = "editor",
      width = math.min(width + 2, vim.o.columns - 8),
      height = math.min(#lines + 1, vim.o.lines - 10),
      row = 4,
      col = 4,
      border = "rounded",
      title = " metadata help ",
      footer = " q close ",
    })
    vim.keymap.set("n", "q", "<cmd>close<cr>", { buffer = help_buf, nowait = true })
  end

  request(client, "rhizome/metadataSchema", { noteId = note_id }, function(err, schema)
    if err or not schema then
      show()
      return
    end
    local extra = {}
    append_schema_section(extra, "Labels", schema.labels)
    append_schema_section(extra, "Relations", schema.relations)
    show(extra)
  end, parent_buf)
end

--- An editable float over a note's title, labels and relations, as YAML
--- (`crates/rhizomed/src/meta.rs` parses it with `marked-yaml`, whose scalars
--- never resolve a type -- `draft: yes` round-trips as the string `"yes"`,
--- not a boolean, so quoting is only ever a YAML-syntax concern). `:w` diffs
--- the edited text against the live note and issues only the ETAPI calls
--- needed to close the gap. The buffer is attached to the same LSP client as
--- note buffers, so completion, hover and diagnostics apply here too.
function M.metadata()
  local note_id, client, _ = current_note()
  if not note_id then
    return
  end
  local name = "trilium-meta://" .. note_id
  local bufnr = vim.fn.bufnr(name)
  if bufnr == -1 then
    bufnr = vim.api.nvim_create_buf(false, false)
    vim.api.nvim_buf_set_name(bufnr, name)
  end
  vim.bo[bufnr].buftype = "acwrite"
  vim.bo[bufnr].swapfile = false
  -- A dedicated filetype, not "yaml" -- so this buffer never triggers a
  -- user's own yaml-language-server autocmd (which would double-attach an
  -- LSP client and fight rhizome's completion/hover). The parser is
  -- registered once in `M.setup`, before any buffer ever sets this
  -- filetype -- setting `filetype` fires `FileType` synchronously, and
  -- registering afterwards left the very first pop-out of a session
  -- unhighlighted (every later one worked, since registration is global
  -- and sticks). `vim.treesitter.start` below is a second, direct
  -- safety net against the same race, independent of nvim-treesitter's own
  -- `FileType` autocmd ever firing at all.
  vim.bo[bufnr].filetype = "rhizomemeta"
  pcall(vim.treesitter.start, bufnr, "yaml")

  local ok, attached = pcall(attach, bufnr)
  if not ok then
    notify(tostring(attached), vim.log.levels.ERROR)
    return
  end
  vim.lsp.inlay_hint.enable(true, { bufnr = bufnr })

  request(client, "rhizome/metadataDocument", { noteId = note_id }, function(err, result)
    if err then
      notify(err.message or vim.inspect(err), vim.log.levels.ERROR)
      return
    end

    set_lines(bufnr, result.text)

    local group = vim.api.nvim_create_augroup("rhizome-meta-" .. bufnr, { clear = true })
    vim.api.nvim_create_autocmd("BufWriteCmd", {
      group = group,
      buffer = bufnr,
      callback = function()
        local text = table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), "\n")
        request(client, "rhizome/applyMetadata", { noteId = note_id, text = text }, function(apply_err, applied)
          if apply_err then
            notify(apply_err.message or vim.inspect(apply_err), vim.log.levels.ERROR)
            return
          end
          set_lines(bufnr, applied.text)
          -- A metadata edit can change the title; treat it the same as
          -- `M.rename` for cache purposes.
          require("rhizome.links").invalidate()
          notify(("metadata saved (%d change%s)"):format(applied.applied, applied.applied == 1 and "" or "s"))
        end, bufnr)
      end,
    })
    vim.api.nvim_create_autocmd("BufWinLeave", {
      group = group,
      buffer = bufnr,
      once = true,
      callback = function()
        vim.diagnostic.reset(nil, bufnr)
      end,
    })

    local width = 0
    for _, line in ipairs(vim.split(result.text, "\n", { plain = true })) do
      width = math.max(width, #line)
    end
    vim.api.nvim_open_win(bufnr, true, {
      relative = "editor",
      width = math.min(math.max(width + 2, 40), vim.o.columns - 4),
      height = math.min(vim.api.nvim_buf_line_count(bufnr) + 1, vim.o.lines - 6),
      row = 2,
      col = 2,
      border = "rounded",
      title = " metadata ",
      footer = " q close | :w apply | g? help ",
    })
    vim.keymap.set("n", "q", "<cmd>close<cr>", { buffer = bufnr, nowait = true })

    -- `gf`/`gd` on a relation's value jumps to the note it names. Bound
    -- explicitly rather than left to `includeexpr`/plain goto-definition:
    -- both would try to open the target *inside* this float (sized and
    -- titled for metadata), so the float has to be closed first. The server
    -- decides whether the cursor is even on a relation value; this only
    -- acts on the answer.
    local function goto_relation()
      local win = vim.api.nvim_get_current_win()
      request(client, "textDocument/definition", position_params(name), function(def_err, location)
        if def_err or not location or location == vim.NIL then
          return
        end
        local target = note_id_from_uri(location.uri)
        if not target then
          return
        end
        if vim.api.nvim_win_is_valid(win) then
          vim.api.nvim_win_close(win, false)
        end
        M.open(target)
      end, bufnr)
    end
    vim.keymap.set("n", "gf", goto_relation, { buffer = bufnr, nowait = true })
    vim.keymap.set("n", "gd", goto_relation, { buffer = bufnr, nowait = true })
    vim.keymap.set("n", "g?", function()
      metadata_help(client, note_id, bufnr)
    end, { buffer = bufnr, nowait = true })
  end)
end

function M.setup(opts)
  state.opts = vim.tbl_deep_extend("force", defaults, opts or {})

  -- Registered once, up front, rather than in `M.metadata` where the
  -- buffer that needs it is actually created -- setting a buffer's
  -- `filetype` fires `FileType` synchronously, and nvim-treesitter's
  -- highlight hook resolves a parser for it right then. Registering after
  -- that point left the first metadata pop-out of a session unhighlighted.
  vim.treesitter.language.register("yaml", "rhizomemeta")

  local group = vim.api.nvim_create_augroup("rhizome", { clear = true })

  vim.api.nvim_create_autocmd("BufWriteCmd", {
    group = group,
    pattern = "trilium://*",
    callback = function(args)
      M.save(args.buf, false)
    end,
  })

  -- Goto-definition on a `[[noteId|Title]]` resolves to a `trilium://` URI, and
  -- Neovim will try to read it like a file. This is what makes that work.
  -- A preview window (quickfix, `:pedit`) renders the buffer the instant this
  -- autocmd returns, so the open must be synchronous and must not steal focus.
  vim.api.nvim_create_autocmd("BufReadCmd", {
    group = group,
    pattern = "trilium://*",
    callback = function(args)
      local note_id = note_id_from_uri(args.file)
      if note_id and not state.buffers[args.buf] then
        M.open(note_id, { focus = false, sync = true, scratch_buf = args.buf })
      end
    end,
  })

  -- Nothing else clears `buffers`/`note_bufnr` for a buffer that closes --
  -- without this, a session that opens and wipes many notes would keep
  -- accumulating stale entries for its whole lifetime.
  vim.api.nvim_create_autocmd("BufWipeout", {
    group = group,
    pattern = "trilium://*",
    callback = function(args)
      local entry = state.buffers[args.buf]
      if entry and state.note_bufnr[entry.note_id] == args.buf then
        state.note_bufnr[entry.note_id] = nil
      end
      state.buffers[args.buf] = nil
    end,
  })

  -- `:w` on a Trilium buffer stays async for responsiveness. Quitting is
  -- different: the process can exit before an in-flight write lands, silently
  -- losing the edit. Flush every dirty Trilium buffer synchronously first.
  local function flush_before_quit()
    for bufnr, entry in pairs(state.buffers) do
      if not entry.read_only and vim.api.nvim_buf_is_valid(bufnr) and vim.bo[bufnr].modified then
        M.save(bufnr, false, true)
      end
    end
    vim.wait(15000, function()
      return state.pending == 0
    end, 20)
  end

  vim.api.nvim_create_autocmd({ "QuitPre", "VimLeavePre" }, {
    group = group,
    pattern = "*",
    callback = flush_before_quit,
  })

  local actions = require("rhizome.actions")
  actions.setup(M)

  vim.api.nvim_create_user_command("Rhizome", function(cmd)
    actions.dispatch(cmd.fargs, cmd.smods)
  end, {
    nargs = "*",
    desc = "Trilium notes: :Rhizome <verb> [args], or :Rhizome actions to browse",
    complete = function(arg_lead, cmd_line)
      return actions.complete(arg_lead, cmd_line)
    end,
  })
end

return M

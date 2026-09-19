--- Live titles for `[[noteId|Title]]` links, rendered over the raw buffer
--- text instead of into it.
---
--- The title stored inside a reference link is dead cache -- Trilium's own
--- renderer (`content_renderer_text.ts`) overwrites it unconditionally with
--- the live note title every time it displays one. Editing rhizome's buffer
--- to match that behavior would mean either rewriting `[[id|title]]` on every
--- rename across every note that links here (expensive, and pointless since
--- nothing reads the stored text), or dropping the title from the buffer
--- format entirely (which makes the raw text unreadable with concealing off).
---
--- Concealing the stored title and drawing the live one as virtual text gets
--- the correct display without either cost: the buffer bytes -- and the
--- round-trip proof that governs them -- are untouched.

local M = {}

local NAMESPACE = vim.api.nvim_create_namespace("rhizome.links")

--- Per-buffer `note_id -> { text, group }`. Populated lazily and read
--- synchronously by every redraw. Without this, each redraw cleared the
--- whole namespace and waited on an LSP round trip before placing anything
--- back -- visible as the raw `[[id|title]]` flashing in every time the
--- cursor crossed a line. With titles cached, a redraw over already-seen
--- links never touches the network, so the clear and the replace land in
--- the same screen frame.
local caches = {}

--- `bufnr -> redraw function`, one entry per attached buffer. `invalidate`
--- uses this to force an immediate repaint -- otherwise a dropped cache
--- entry would sit invisible until the next cursor move happened to cross
--- that link's line.
local attached = {}

local function cache_for(bufnr)
  local cache = caches[bufnr]
  if not cache then
    cache = {}
    caches[bufnr] = cache
  end
  return cache
end

--- Drop cached titles and repaint. With a `bufnr`, only that buffer; with
--- none, every attached buffer -- used after a rename, since any open
--- buffer anywhere could hold a link to the note that changed.
function M.invalidate(bufnr)
  if bufnr then
    caches[bufnr] = nil
    local redraw = attached[bufnr]
    if redraw then
      redraw()
    end
    return
  end
  caches = {}
  for _, redraw in pairs(attached) do
    redraw()
  end
end

--- Trilium link targets are sometimes a bare noteId and sometimes a full
--- notePath (a `/`-joined chain of ancestors ending in the target, e.g.
--- `abc123/def456/ghi789`) -- Trilium itself emits either form depending on
--- how the link was made, even linking one note both ways from different
--- pages of its own User Guide. The note is always the last non-empty
--- segment. Mirrors `note_id_of_path` in `text.rs`.
local function note_id_of_path(s)
  local tail = s
  for segment in s:gmatch("[^/]+") do
    tail = segment
  end
  return tail
end

--- `[[noteId]]` or `[[noteId|Title]]`, byte-indexed within a line. `note_id`
--- is the link target exactly as written (sometimes a notePath); `target`
--- is that path's resolved note, which is what the title cache and jump
--- commands actually key on.
---
--- `stored` / `stored_col` describe the title cached inside the link, when it
--- has one: the text after the `|`, and the 0-based byte column it starts at.
--- `place` uses them to render that text in situ instead of as virtual text --
--- see the wrap note there.
local function links_on_line(line)
  local out = {}
  local i = 1
  while true do
    local open = line:find("[[", i, true)
    if not open then
      break
    end
    local close = line:find("]]", open + 2, true)
    if not close then
      break
    end
    local inner = line:sub(open + 2, close - 1)
    local note_id = inner:match("^([^|]+)")
    if note_id and note_id ~= "" and not inner:find("\n", 1, true) then
      local bar = inner:find("|", 1, true)
      note_id = vim.trim(note_id)
      table.insert(out, {
        note_id = note_id,
        target = note_id_of_path(note_id),
        start_col = open - 1,
        end_col = close + 1,
        -- 1-based `bar` is an index into `inner`, which itself starts at
        -- `open + 2`; the stored title begins one byte past the `|`, so its
        -- 0-based column in `line` is `(open + 2 - 1) + bar`.
        stored = bar and inner:sub(bar + 1) or nil,
        stored_col = bar and (open + 1 + bar) or nil,
      })
    end
    i = close + 2
  end
  return out
end

--- The link containing byte column `col` (0-based) on `line`, if any.
--- Strict on the upper bound, unlike the server's `link_at` in `text.rs`
--- (which allows the closing `]]` itself as a hover/definition target): the
--- character right after `]]` is ordinary text, and `gf` there should behave
--- like `gf` anywhere else instead of being captured by the link.
function M.link_at(line, col)
  for _, link in ipairs(links_on_line(line)) do
    if col >= link.start_col and col < link.end_col then
      return link
    end
  end
end

--- Place extmarks for links in `by_line` whose title is already cached. If
--- `only_ids` is given, restrict placement to those ids (used for the
--- second, post-fetch pass, so already-placed links are not duplicated).
--- Keyed on `target`, not `note_id`, so a note linked once by bare id and
--- once by notePath elsewhere in the same buffer shares one cache entry and
--- one fetch. Returns the targets that still have no cached title.
---
--- Two ways to draw a link, picked per link:
---
--- * When the title stored in the buffer already matches the live one -- the
---   overwhelmingly common case, since the stored copy is only stale between a
---   rename and the next sync -- conceal just the `[[id|` prefix and the `]]`
---   suffix and let the stored title render as ordinary buffer text.
--- * Otherwise conceal the whole link and draw the live title as inline
---   virtual text, which is the only way to show text the buffer doesn't
---   contain.
---
--- The split exists for `'wrap'`. Concealed cells still occupy layout columns
--- (neovim/neovim#14409, inherited from vim/vim#260), so hiding the link never
--- buys back width -- but inline virtual text *adds* its own width on top of
--- the concealed span it replaces. Measured on 0.12.5, for a line holding two
--- links whose stored titles are current, the minimum window width to keep it
--- on one screen row:
---
---     raw text, no marks .................. raw width
---     conceal-only (this fast path) ....... raw width
---     conceal + inline virt_text .......... raw width + both titles
---
--- So the fast path costs nothing beyond the conceal bug itself, while the
--- virt_text path made every link pay twice and wrapped lines that had room.
--- `tests/links.lua` asserts exactly this. `virt_text_pos = "overlay"` also
--- avoids the extra width, but it overwrites the text following a link rather
--- than displacing it, so it is not an option.
---
--- TODO: drop this split and always use the virt_text path once conceal-aware
--- `'wrap'` lands (neovim/neovim#40897, milestoned for 0.13) and the pinned
--- neovim is new enough -- then the fast path saves nothing and the stale-text
--- window below goes away.
--- TODO: drop this split and always use the virt_text path once conceal-aware
--- `'wrap'` lands (neovim/neovim#40897, milestoned for 0.13) and the pinned
--- neovim is new enough -- then the fast path saves nothing and the stale-text
--- window below goes away.
local function place(bufnr, by_line, cache, only_ids)
  local missing, seen_missing = {}, {}
  for lnum, links in pairs(by_line) do
    for _, link in ipairs(links) do
      if not only_ids or only_ids[link.target] then
        local entry = cache[link.target]
        if entry then
          if link.stored == entry.text then
            -- Conceal `[[id|` and `]]` around the stored title, which stands
            -- in for the live one. Two marks, so the title between them stays
            -- real text and keeps its layout columns.
            pcall(vim.api.nvim_buf_set_extmark, bufnr, NAMESPACE, lnum, link.start_col, {
              end_col = link.stored_col,
              conceal = "",
            })
            pcall(vim.api.nvim_buf_set_extmark, bufnr, NAMESPACE, lnum, link.end_col - 2, {
              end_col = link.end_col,
              conceal = "",
            })
            -- The stored title is buffer text, so it carries the buffer's own
            -- markdown highlighting; this repaints it as a link.
            pcall(vim.api.nvim_buf_set_extmark, bufnr, NAMESPACE, lnum, link.stored_col, {
              end_col = link.end_col - 2,
              hl_group = entry.group,
            })
          else
            -- `virt_text` is drawn regardless of `conceallevel`, but the
            -- `conceal` that hides the link it replaces is not. With
            -- concealing inactive both render, giving
            -- `Renamed Note[[id|Stored Title]]`. There is nothing useful to
            -- draw in that case -- the buffer already shows a title, just a
            -- stale one -- so leave the raw link alone and let the next sync
            -- reconcile it.
            if vim.wo.conceallevel > 0 then
              pcall(vim.api.nvim_buf_set_extmark, bufnr, NAMESPACE, lnum, link.start_col, {
                end_col = link.end_col,
                conceal = "",
                virt_text = { { entry.text, entry.group } },
                virt_text_pos = "inline",
              })
            end
          end
        elseif not seen_missing[link.target] then
          seen_missing[link.target] = true
          table.insert(missing, link.target)
        end
      end
    end
  end
  return missing
end

--- Redraw every link on `bufnr` except `skip_line` (0-based), which is left
--- as raw text so it can be edited normally.
local function render(bufnr, client, skip_line)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

  local by_line = {}
  for lnum, line in ipairs(lines) do
    if lnum - 1 ~= skip_line then
      local links = links_on_line(line)
      if #links > 0 then
        by_line[lnum - 1] = links
      end
    end
  end

  local cache = cache_for(bufnr)
  vim.api.nvim_buf_clear_namespace(bufnr, NAMESPACE, 0, -1)
  local missing = place(bufnr, by_line, cache)
  if #missing == 0 then
    return
  end

  local ok, req = pcall(require, "rhizome")
  if not ok then
    return
  end
  req._request(client, "rhizome/titles", { noteIds = missing }, function(err, titles)
    if err or not titles or not vim.api.nvim_buf_is_valid(bufnr) then
      return
    end
    local fetched = {}
    for _, target in ipairs(missing) do
      local title = titles[target]
      if title == nil or title == vim.NIL then
        cache[target] = { text = "[missing note]", group = "RhizomeLinkBroken" }
      else
        cache[target] = { text = title, group = "RhizomeLink" }
      end
      fetched[target] = true
    end
    place(bufnr, by_line, cache, fetched)
  end)
end

--- Wire up conceal-and-reveal for `bufnr`. Called once per Trilium buffer.
--- Window-local options (`conceallevel`, `concealcursor`) are set alongside
--- fold options in `rhizome.apply_window_options`, not here -- see that
--- function for why they can't be set at buffer-construction time.
function M.attach(bufnr, client)
  vim.cmd.highlight({ "default", "link", "RhizomeLink", "Underlined" })
  vim.cmd.highlight({ "default", "link", "RhizomeLinkBroken", "ErrorMsg" })

  local group = vim.api.nvim_create_augroup("rhizome-links-" .. bufnr, { clear = true })
  local last_line

  local function redraw()
    local ok, cursor = pcall(vim.api.nvim_win_get_cursor, 0)
    local line = ok and (cursor[1] - 1) or nil
    last_line = line
    render(bufnr, client, line)
  end
  local function redraw_if_moved()
    local ok, cursor = pcall(vim.api.nvim_win_get_cursor, 0)
    local line = ok and (cursor[1] - 1) or nil
    if line == last_line then
      return
    end
    redraw()
  end

  vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI", "TextChanged", "TextChangedI" }, {
    group = group,
    buffer = bufnr,
    callback = redraw_if_moved,
  })
  vim.api.nvim_create_autocmd("BufWipeout", {
    group = group,
    buffer = bufnr,
    callback = function()
      caches[bufnr] = nil
      attached[bufnr] = nil
    end,
  })
  attached[bufnr] = redraw
  redraw()
end

--- Place marks for every link in `bufnr` from an already-known
--- `target -> title` map, skipping the server round trip. Exists so
--- `tests/links.lua` can drive the real placement path -- the rendering it
--- asserts on is the whole point of the module, and is not reachable without
--- either a live Trilium or a seam like this.
function M._test_place(bufnr, titles)
  local by_line, cache = {}, {}
  for lnum, line in ipairs(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)) do
    local found = links_on_line(line)
    if #found > 0 then
      by_line[lnum - 1] = found
    end
  end
  for target, title in pairs(titles) do
    cache[target] = { text = title, group = "RhizomeLink" }
  end
  return place(bufnr, by_line, cache)
end

return M

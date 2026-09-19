--- Neovim-harness tests for lua/rhizome/links.lua. Unlike date.lua these need
--- a real `vim`, since the thing under test is extmark placement and the thing
--- being asserted is what lands on screen. Run from the repo root with:
---
---   RHIZOME_LUA="$PWD/lua" nvim --headless -u NORC -l tests/links.lua
---
--- (the module directory comes from the environment rather than a path derived
--- from `arg[0]`, so the test still resolves it when nix runs it from a store
--- path.)
---
--- Two properties are checked, both regressions that a pure unit test of the
--- parser would miss:
---
--- 1. The rendered line reads as titles, with the `[[id|` scaffolding gone and
---    the text after a link intact.
--- 2. A line of links fits on one screen row without paying for the titles
---    twice. This is what regressed: inline virt_text added its own width on
---    top of the concealed span it replaced, so lines wrapped early.
---
--- Widths are derived from the fixture rather than hardcoded, so the numbers
--- stay correct if the fixture changes. `RAW_WIDTH` is the floor only because
--- concealed cells still occupy layout columns (neovim/neovim#14409); if that
--- is fixed upstream (neovim/neovim#40897) the floor drops to the visible
--- width and this assertion needs revisiting -- see the TODO in links.lua.

--- Load the module under test *by path*, not by `require`. Neovim resolves
--- `require("rhizome.links")` through its runtime path, which in a session with
--- the plugin installed finds the copy in the nix store -- so a plain `require`
--- here would silently test the installed build instead of the working tree.
local SRC = (os.getenv("RHIZOME_LUA") or "./lua") .. "/rhizome/links.lua"
local chunk, load_err = loadfile(SRC)
if not chunk then
  print("ABORT: could not load " .. SRC .. ": " .. tostring(load_err))
  vim.cmd("cquit 1")
end
local links = chunk()

local failures = 0
local function eq(got, want, label)
  if got ~= want then
    failures = failures + 1
    print(string.format("FAIL %s:\n  got  %s\n  want %s", label, vim.inspect(got), vim.inspect(want)))
  end
end

vim.o.lines = 40
vim.o.columns = 250

--- Render `line` in a window `width` columns wide, with `titles` standing in
--- for what the server would return, and report both what is on screen and
--- how many screen rows it took. `conceallevel` defaults to 2 (what rhizome
--- sets when `link_titles` is on); pass 0 to check the concealing-off path.
local function render(line, titles, width, conceallevel)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { line })
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    row = 0,
    col = 0,
    width = width,
    height = 20,
    style = "minimal",
  })
  vim.wo[win].wrap = true
  vim.wo[win].linebreak = true
  vim.wo[win].conceallevel = conceallevel or 2
  vim.wo[win].concealcursor = "nvic"

  -- Drive the real code path: seed the cache the way a `rhizome/titles`
  -- response would, then let `attach`'s redraw place the marks.
  links._test_place(buf, titles)

  local height = vim.api.nvim_win_text_height(win, {}).all
  vim.cmd("redraw")
  local cells = {}
  for col = 1, width do
    cells[#cells + 1] = vim.fn.screenstring(1, col)
  end
  local screen = (table.concat(cells):gsub("%s+$", ""))
  vim.api.nvim_win_close(win, true)
  return screen, height
end

--- The narrowest window in which `line` still fits on a single screen row.
local function fit_width(line, titles)
  for width = 10, 240 do
    local _, height = render(line, titles, width)
    if height == 1 then
      return width
    end
  end
end

-- ---------------------------------------------------------------------------
-- A list item carrying two links, each with a stored title matching the live
-- one. This is the shape that regressed: several links on one prose line.
-- ---------------------------------------------------------------------------

local ONE, TWO = "First Note", "Second Note"
local LINE = "- links to [[noteAAAAAAAA|" .. ONE .. "]] and [[noteBBBBBBBB|" .. TWO .. "]]"
local FRESH = { noteAAAAAAAA = ONE, noteBBBBBBBB = TWO }
local VISIBLE = "- links to " .. ONE .. " and " .. TWO
local RAW_WIDTH = #LINE -- the floor imposed by #14409
local VIRT_WIDTH = RAW_WIDTH + #ONE + #TWO -- what the old unconditional path cost

eq(render(LINE, FRESH, 120), VISIBLE, "stored titles current: renders as titles")

-- The regression: placing the titles must not cost width on top of the
-- concealed spans they stand in for.
eq(fit_width(LINE, FRESH), RAW_WIDTH, "stored titles current: no width beyond the conceal floor")

-- Guard against the assertion above going vacuous: it is only meaningful
-- while the conceal floor is genuinely cheaper than the virt_text path.
if RAW_WIDTH >= VIRT_WIDTH then
  failures = failures + 1
  print("FAIL width assertion is vacuous: fixture has no titles to save")
end

-- ---------------------------------------------------------------------------
-- Stale stored title: the buffer says one thing, the server another. The live
-- title must win, even though showing it costs width.
-- ---------------------------------------------------------------------------

local RENAMED = { noteAAAAAAAA = "Renamed Note", noteBBBBBBBB = TWO }
eq(
  render(LINE, RENAMED, 140),
  "- links to Renamed Note and " .. TWO,
  "stale stored title: live title wins"
)

-- ---------------------------------------------------------------------------
-- A link with no stored title at all has nothing to fall back on, so it must
-- take the virt_text path -- and must not swallow the text after it, which is
-- what ruled out `virt_text_pos = "overlay"`.
-- ---------------------------------------------------------------------------

eq(
  render("hi [[abc]] bye", { abc = "A Live Title" }, 80),
  "hi A Live Title bye",
  "bare id: live title rendered, trailing text intact"
)

eq(
  render("hi [[abc|Old]] bye", { abc = "A Much Longer New Title" }, 80),
  "hi A Much Longer New Title bye",
  "stale + longer title: trailing text intact"
)

-- ---------------------------------------------------------------------------
-- notePath targets resolve to their last segment, and share a cache entry with
-- the same note linked by bare id.
-- ---------------------------------------------------------------------------

eq(
  render("see [[root/mid/abc|Note]] and [[abc|Note]]", { abc = "Note" }, 80),
  "see Note and Note",
  "notePath and bare id share a title"
)

-- ---------------------------------------------------------------------------
-- Concealing off (`link_titles = false`, the current default). `virt_text` is
-- drawn whatever `conceallevel` says, but the `conceal` hiding the text it
-- replaces is not -- so the stale-title path must draw nothing at all here,
-- or the line renders as `Renamed Note[[id|Stored Title]]`.
-- ---------------------------------------------------------------------------

eq(render(LINE, FRESH, 140, 0), LINE, "conceal off: fresh titles render as raw text")
eq(render(LINE, RENAMED, 140, 0), LINE, "conceal off: stale title does not double-render")
eq(
  render("hi [[abc]] bye", { abc = "A Live Title" }, 80, 0),
  "hi [[abc]] bye",
  "conceal off: bare id does not double-render"
)

-- ---------------------------------------------------------------------------
-- link_at: the column arithmetic the jump commands depend on. `stored_col`
-- shares that arithmetic, so a bug here is a bug in placement.
-- ---------------------------------------------------------------------------

local probe = "ab [[xyz|Title]] cd"
local open_col = 3 -- 0-based column of the first `[`
eq(links.link_at(probe, open_col).target, "xyz", "link_at: at `[[`")
eq(links.link_at(probe, 15).target, "xyz", "link_at: on final `]`")
eq(links.link_at(probe, 16), nil, "link_at: past `]]` is not a link")
eq(links.link_at(probe, 2), nil, "link_at: before `[[` is not a link")
eq(links.link_at("no links here", 4), nil, "link_at: plain text")
eq(links.link_at("unclosed [[abc", 11), nil, "link_at: unterminated link")

if failures > 0 then
  print(string.format("%d failure(s)", failures))
  vim.cmd("cquit 1")
end
print("ok")
vim.cmd("qa!")

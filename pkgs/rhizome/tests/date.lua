--- Plain-Lua tests for lua/rhizome/date.lua -- no Neovim harness needed,
--- since date.lua has no `vim` dependency. Run with:
---
---   TZ=Europe/Berlin TZDIR=<tzdata>/share/zoneinfo lua tests/date.lua
---
--- The TZ probe at the top matters: if TZDIR points at the wrong tzdata
--- output (or is missing), glibc silently falls back to UTC and every DST
--- assertion below passes vacuously without testing anything.

package.path = (arg[0]:match("(.*/)") or "./") .. "../lua/?.lua;" .. package.path
local date = require("rhizome.date")

local failures = 0

local function eq(got, want, label)
  if got ~= want then
    failures = failures + 1
    print(string.format("FAIL %s: got %s, want %s", label, tostring(got), tostring(want)))
  end
end

local function at(y, mo, d, h, mi)
  return os.time({ year = y, month = mo, day = d, hour = h, min = mi or 0, sec = 0 })
end

-- Confirm the timezone actually took effect before trusting anything below.
local probe = os.date("!%H", at(2026, 8, 2, 12, 0))
if probe ~= "10" then
  print(
    string.format(
      "ABORT: expected Europe/Berlin (UTC+2 in August) but got UTC hour %s -- "
        .. "check TZ/TZDIR are set correctly",
      probe
    )
  )
  os.exit(1)
end

-- The regression this module exists to fix: `today` must not depend on
-- which side of noon `now` falls on.
for _, h in ipairs({ 0, 11, 12, 13, 23 }) do
  eq(date.iso(0, at(2026, 8, 2, h, 30)), "2026-08-02", "noon boundary h=" .. h)
end

-- yesterday/tomorrow in the evening (the case originally reported).
eq(date.keyword("yesterday", at(2026, 8, 2, 20, 0)), "2026-08-01", "yesterday in the evening")
eq(date.keyword("today", at(2026, 8, 2, 20, 0)), "2026-08-02", "today in the evening")
eq(date.keyword("tomorrow", at(2026, 8, 2, 20, 0)), "2026-08-03", "tomorrow in the evening")

-- Unknown keywords are not this module's problem.
eq(date.keyword("nonsense", at(2026, 8, 2, 12, 0)), nil, "unknown keyword")

-- Month/year rollover, both directions.
eq(date.iso(1, at(2026, 1, 31, 23, 30)), "2026-02-01", "month rollover")
eq(date.iso(-1, at(2026, 3, 1, 0, 30)), "2026-02-28", "month rollback")
eq(date.iso(1, at(2026, 12, 31, 23, 30)), "2027-01-01", "year rollover")

-- DST transitions: Europe/Berlin springs forward 2026-03-29 and falls back
-- 2026-10-25. `today` must land on the same calendar day regardless of
-- clock time, on the transition day and the days either side of it.
local dst_days = { { 3, 28 }, { 3, 29 }, { 3, 30 }, { 10, 24 }, { 10, 25 }, { 10, 26 } }
for _, md in ipairs(dst_days) do
  local month, day = md[1], md[2]
  local want = string.format("2026-%02d-%02d", month, day)
  for _, h in ipairs({ 0, 12, 23 }) do
    eq(date.iso(0, at(2026, month, day, h, 30)), want, string.format("dst %s h=%d", want, h))
  end
end

if failures == 0 then
  print("all date.lua tests passed")
  os.exit(0)
else
  print(failures .. " failure(s)")
  os.exit(1)
end

--- Pure date arithmetic for the "today"/"yesterday"/"tomorrow" keywords and
--- the inbox. Deliberately free of any `vim` dependency so it can be
--- exercised with a plain `lua` interpreter (see `tests/date.lua`) rather
--- than a full Neovim test harness.

local M = {}

local OFFSETS = { today = 0, yesterday = -1, tomorrow = 1 }

--- `offset` days from `now` (defaults to the real current time; a caller
--- passes an explicit `now` only in tests), as an ISO date.
---
--- Adding `offset * 86400` seconds directly to `now` is wrong twice over:
--- past local noon it rolls the date forward by adding wall-clock hours to
--- an instant that is already past the day's midpoint, and whole-day
--- seconds arithmetic across a DST transition lands an hour either side of
--- midnight. Anchoring at local noon and then shifting the broken-down
--- `day` field keeps the +-1h DST slop 12 hours away from any date
--- boundary, and lets `os.time` normalise an out-of-range `day` into
--- month/year rollover for free. `isdst = nil` lets `mktime` figure out
--- DST for the target day itself rather than trusting a flag computed for
--- `now`, which can be wrong across a transition.
function M.iso(offset, now)
  local t = os.date("*t", now or os.time())
  t.hour, t.min, t.sec = 12, 0, 0
  t.isdst = nil
  t.day = t.day + (offset or 0)
  return os.date("%Y-%m-%d", os.time(t))
end

--- `keyword` ("today", "yesterday", "tomorrow") -> an ISO date, or `nil` if
--- `keyword` isn't one of those.
function M.keyword(keyword, now)
  local offset = OFFSETS[keyword]
  if not offset then
    return nil
  end
  return M.iso(offset, now)
end

--- Today's ISO date -- what the inbox is keyed by.
function M.today(now)
  return M.iso(0, now)
end

return M

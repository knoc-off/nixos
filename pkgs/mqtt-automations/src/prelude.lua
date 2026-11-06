-- Loaded before every room file. A room file is one room{} call: a state
-- machine the engine (src/room.rs) runs. Everything here only builds tables
-- and small functions.
--
--   room{
--     presence = { "<z2m device>", ... },     -- events present / absent
--     doors    = { <name> = "<z2m device>" }, -- events <name>.open / .closed
--     buttons  = { <name> = "<z2m device>" }, -- events <name>.<action>
--     triggers = { <name> = function(c) end },-- event <name> when it turns true
--     default  = "<state>",  -- after a reset; where `resume` goes by default
--     start    = "<state>",  -- at startup (default: default)
--     forget_after = secs,   -- how long `resume` remembers (default 3600)
--     states = {
--       <name> = {
--         hidden = true,        -- a phase, not a mode: not in HA's dropdown
--                               -- and never what `resume` returns to
--         extends = "<state>",  -- start from another state: look fields
--                               -- and `on` merge, its `when` rows go last
--         look = { on, brightness, color_temp, transition },
--         per_light = { <light> = { <look fields> } },
--         on = { <event> = "<state>" | row | { row, ... } },
--         when = { row, ... },  -- checked all the time
--       },
--     },
--   }
--
-- Rows: { to = "<state>" | "resume", <conditions> } or
-- { toggle = { <light>, ... }, <conditions> }. The first row whose
-- conditions all hold is taken. Conditions: present = bool;
-- absent_for, time_in_state = secs (at least); between, outside =
-- { from_hour, to_hour }; test = function(c) -> bool.
--
-- Look: brightness 1-254, color_temp in mireds, transition in seconds (used
-- when the state is entered; while it lasts, changes glide over 2s). Any
-- value may be a function(c). c = { light, state, present, present_for,
-- absent_for, time_in_state, clock }. A state without a look leaves the
-- lights alone; `manual` is such a state and always exists.
--
-- Manual changes (HA, the app, a wall switch, a toggle row) hold until the
-- room changes state. Leaving a mode (a state that isn't hidden) remembers
-- it with its manual changes; `resume` goes back to it within
-- forget_after, else to the default.

local function clamp(x, lo, hi)
  return math.max(lo, math.min(hi, x))
end

local function copy(a, b)
  if a == nil and b == nil then return nil end
  local out = {}
  for k, v in pairs(a or {}) do out[k] = v end
  for k, v in pairs(b or {}) do out[k] = v end
  return out
end

local STATE_KEYS = { hidden = true, extends = true, look = true, per_light = true, on = true, when = true }

function room(spec)
  local states = spec.states or {}
  states.manual = states.manual or {}
  local done, busy = {}, {}
  local function resolve(name)
    if done[name] then return done[name] end
    local s = states[name]
    if type(s) ~= "table" then error("no state " .. tostring(name), 0) end
    if busy[name] then error("state " .. name .. ": extends loop", 0) end
    for k in pairs(s) do
      if not STATE_KEYS[k] then error("state " .. name .. ": unknown key " .. tostring(k), 0) end
    end
    busy[name] = true
    local out = { hidden = s.hidden, look = s.look, per_light = s.per_light, on = s.on, when = s.when }
    if s.extends then
      local p = resolve(s.extends)
      out.look = copy(p.look, s.look)
      out.on = copy(p.on, s.on)
      out.when = {}
      for _, r in ipairs(s.when or {}) do table.insert(out.when, r) end
      for _, r in ipairs(p.when or {}) do table.insert(out.when, r) end
      if p.per_light or s.per_light then
        out.per_light = {}
        for l, v in pairs(p.per_light or {}) do out.per_light[l] = v end
        for l, v in pairs(s.per_light or {}) do out.per_light[l] = copy(out.per_light[l], v) end
      end
    end
    done[name] = out
    return out
  end
  local resolved = {}
  for name in pairs(states) do resolved[name] = resolve(name) end
  __room(copy(spec, { states = resolved }))
end

-- Each light's HA knobs, on the topics the old sun-follow daemons used, so
-- existing values carry over.
local knobs = {}
for name, l in pairs(lights) do
  local base = "mqtt-auto/sun-follow/" .. l.device .. "/"
  if l.dimmable then
    knobs[name] = {
      min = setting(base .. "min-brightness", 5),
      max = setting(base .. "max-brightness", 100),
      gamma = setting(base .. "gamma", 1),
    }
  else
    knobs[name] = {
      threshold = setting(base .. "threshold", 15),
      invert = setting(base .. "invert", false),
    }
  end
end
local follow_ct = setting("mqtt-auto/color-temp-cycle/enabled", true)

-- A look following the sun: brightness from 0 up to each light's HA max,
-- along its curve knob, never below its brightness floor (the old
-- min-brightness topic) -- so the floor is what evenings and nights get,
-- and the day isn't squeezed above it. Colour temperature follows the day
-- (HA "Lights follow hue"). `floor` (percent, or a function(c) returning
-- it) raises the floor further; any look field given replaces the sun's.
function sunlight(o)
  o = o or {}
  local look = {
    brightness = function(c)
      local k = knobs[c.light]
      if not k.min then return 254 end
      local max = clamp(k.max(), 0, 100)
      local floor = o.floor
      if type(floor) == "function" then floor = floor(c) end
      floor = math.min(math.max(clamp(k.min(), 0, 100), floor or 0), max)
      local curve = sun.level{ min = 0, max = max, gamma = clamp(k.gamma(), 0.1, 10) }
      return math.max(curve, math.max(1, math.floor(floor / 100 * 254 + 0.5)))
    end,
    color_temp = function()
      return follow_ct() and sun.ct() or nil
    end,
  }
  for k, v in pairs(o) do
    if k ~= "floor" then look[k] = v end
  end
  return look
end

-- A plug look: on while the daylight fraction is at or above its HA
-- threshold (below it, inverted).
function sun_switch()
  return {
    on = function(c)
      local k = knobs[c.light]
      if not k.threshold then error(c.light .. " is not a plug", 0) end
      local f = sun.daylight()
      if k.invert() then f = 1 - f end
      return f >= clamp(k.threshold(), 0, 100) / 100
    end,
  }
end

-- The fixed-clock wake-up ramp on the HA "Sunrise ..." settings.
-- Deliberately not the real sun: that would be a 9 hour ramp from 03:50 in
-- June. `active()`: inside the ramp. `level()`: its brightness now, and its
-- peak once it is over.
function wake_ramp()
  local base = "mqtt-auto/sunrise-lights/"
  local at = setting(base .. "start-time", "06:30:00")
  local minutes = setting(base .. "duration", 45)
  local max = setting(base .. "max-brightness", 30)
  local gamma = setting(base .. "gamma", 2.2)
  local function progress()
    local h, m = tostring(at()):match("^(%d+):(%d+)")
    local total = minutes()
    if not h or total <= 0 then return nil end
    local elapsed = (clock() - tonumber(h) - tonumber(m) / 60) % 24 * 60
    if elapsed >= total then return nil end
    return elapsed / total
  end
  return {
    active = function() return progress() ~= nil end,
    level = function()
      local t = progress() or 1
      -- Smoothstep, then gamma to spend longer at the dim end.
      local r = (t * t * (3 - 2 * t)) ^ clamp(gamma(), 0.1, 10)
      return math.max(1, math.floor(r * clamp(max(), 0, 100) / 100 * 254 + 0.5))
    end,
  }
end

-- HA's bright / dim / night modes: `base` at a fixed brightness (and warm,
-- for night), otherwise behaving like it.
function scenes(base, states)
  states.bright = { extends = base, look = { brightness = 254 } }
  states.dim = { extends = base, look = { brightness = 76 } }
  states.night = { extends = base, look = { brightness = 8, color_temp = 454 } }
  return states
end

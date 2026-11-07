-- Day: on at the sun's level while someone is here, with a floor that rises
-- the longer they stay (up to 40% after two hours, 08:00-20:00) and starts
-- low again after they leave. Off 30 minutes after the sensor last saw
-- anyone (sitting still at the desk). While the house sleeps, arriving
-- switches nothing on, so moving in bed never lights the room.
--
-- Button: single -> bedtime, a dim warm light; in bedtime, single switches
-- it off and on again. Hold: wind down -- dim now, off after five minutes.
-- Double: back to day. The wake ramp (HA "Sunrise ..." settings) takes over
-- from all of them.
--
-- This room puts the house to sleep: bedtime and wind down announce night
-- (so does 02:00, if nobody did). The wake ramp, a double press, or 09:00
-- at the latest announce day. It doesn't follow the house itself.
local LOW = 25 -- of 254
local ramp = wake_ramp()

local function floor(c)
  if c.clock < 8 or c.clock >= 20 then return 0 end
  return 40 * math.min(1, c.time_in_state / 7200)
end

local buttons = {
  ["button.single"] = { to = "bedtime", announce = "night" },
  ["button.hold"] = { to = "winddown", announce = "night" },
  ["button.double"] = { to = "day", announce = "day" },
  wake = { to = "wake", announce = "day" },
  late = { announce = "night" },
  morning = { announce = "day" },
}
local function with(on)
  local t = {}
  for k, v in pairs(buttons) do t[k] = v end
  for k, v in pairs(on) do t[k] = v end
  return t
end

room{
  presence = { "bedroom_presence" },
  buttons = { button = "bedroom_button" },
  triggers = {
    wake = ramp.active,
    late = function() return clock() >= 2 and clock() < 3 end,
    morning = function() return clock() >= 9 and clock() < 10 end,
  },
  default = "day",
  start = "off",
  states = scenes("day", {
    off = {
      hidden = true,
      look = { on = false, transition = 30 },
      on = with{ present = { to = "resume", test = function(c) return c.house ~= "night" end } },
    },
    day = {
      look = sunlight{ floor = floor },
      on = with{},
      when = { { to = "off", absent_for = 1800 } },
    },
    -- Ramps up, then stays at its peak until the room empties. Whoever
    -- sleeps through it may be invisible to the sensor, so absence only
    -- counts once the ramp is over.
    wake = {
      look = sunlight{ brightness = ramp.level },
      on = with{},
      when = { { to = "off", absent_for = 1800, test = function() return not ramp.active() end } },
    },
    bedtime = {
      look = { brightness = LOW, color_temp = 454 },
      on = with{ ["button.single"] = "bedtime_off" },
      when = { { to = "off", absent_for = 1800 } },
    },
    bedtime_off = {
      hidden = true,
      look = { on = false },
      on = with{},
      when = { { to = "off", absent_for = 1800 } },
    },
    winddown = {
      extends = "bedtime",
      when = { { to = "bedtime_off", time_in_state = 300 } },
    },
  }),
}

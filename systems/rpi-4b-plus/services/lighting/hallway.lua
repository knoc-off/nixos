-- On at the sun's level while someone is about; off a minute after the
-- sensor last saw anyone, fading over 30 seconds. While the house sleeps: a
-- faint warm light, off 30 seconds after.
local function awake(c) return c.house ~= "night" end

room{
  presence = { "hallway_motion" },
  default = "auto",
  start = "off",
  states = {
    off = {
      hidden = true,
      look = { on = false, transition = 30 },
      on = { present = "resume" },
    },
    auto = {
      look = sunlight(),
      when = { { to = "off", absent_for = 60 }, { to = "night", house = "night" } },
    },
    night = {
      hidden = true,
      forget = true, -- the morning starts afresh, not with last evening's changes
      look = { brightness = 8, color_temp = 454, transition = 1 },
      when = { { to = "resume", test = awake }, { to = "off", absent_for = 30 } },
    },
  },
}

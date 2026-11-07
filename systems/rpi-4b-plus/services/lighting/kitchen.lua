-- On at the sun's level while someone is about; off five minutes after the
-- sensor last saw anyone, fading over a minute. While the house sleeps: dim
-- and warm, off two minutes after. The plug is not a light: it is left to
-- whoever switches it (devices.nix keeps it out of the room).
local function awake(c) return c.house ~= "night" end

room{
  presence = { "kitchen_motion" },
  default = "auto",
  start = "off",
  states = {
    off = {
      hidden = true,
      look = { on = false, transition = 60 },
      on = { present = "resume" },
    },
    auto = {
      look = sunlight(),
      when = { { to = "off", absent_for = 300 }, { to = "night", house = "night" } },
    },
    night = {
      hidden = true,
      look = { brightness = 25, color_temp = 454, transition = 1 },
      when = { { to = "resume", test = awake }, { to = "off", absent_for = 120 } },
    },
  },
}

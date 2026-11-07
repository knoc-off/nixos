-- On at the sun's level while someone is about; off five minutes after the
-- sensor last saw anyone, fading over a minute. While the house sleeps: dim
-- and warm, off two minutes after. The plug is not a light: it is left to
-- whoever switches it (devices.nix keeps it out of the room).
local back = { { to = "night", house = "night" }, { to = "resume" } }

room{
  presence = { "kitchen_motion" },
  default = "auto",
  start = "off",
  states = {
    off = {
      hidden = true,
      look = { on = false, transition = 60 },
      on = { present = back },
    },
    auto = {
      look = sunlight(),
      on = { ["house.night"] = "night" },
      when = { { to = "off", absent_for = 300 } },
    },
    night = {
      hidden = true,
      look = { brightness = 25, color_temp = 454, transition = 1 },
      on = { ["house.day"] = "resume", ["house.bright"] = "resume" },
      when = { { to = "off", absent_for = 120 } },
    },
  },
}

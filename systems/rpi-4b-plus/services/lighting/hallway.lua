-- On at the sun's level while someone is about; off a minute after the
-- sensor last saw anyone, fading over 30 seconds. While the house sleeps: a
-- faint warm light, off 30 seconds after.
local back = { { to = "night", house = "night" }, { to = "resume" } }

room{
  presence = { "hallway_motion" },
  default = "auto",
  start = "off",
  states = scenes("auto", {
    off = {
      hidden = true,
      look = { on = false, transition = 30 },
      on = { present = back },
    },
    auto = {
      look = sunlight(),
      on = { ["house.night"] = "night" },
      when = { { to = "off", absent_for = 60 } },
    },
    night = {
      hidden = true,
      look = { brightness = 8, color_temp = 454, transition = 1 },
      on = { ["house.day"] = "resume" },
      when = { { to = "off", absent_for = 30 } },
    },
  }),
}

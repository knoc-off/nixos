-- On at the sun's level while someone is about; off a minute after the
-- sensor last saw anyone, fading over 30 seconds.
room{
  presence = { "hallway_motion" },
  default = "auto",
  start = "off",
  states = scenes("auto", {
    off = {
      hidden = true,
      look = { on = false, transition = 30 },
      on = { present = "resume" },
    },
    auto = {
      look = sunlight(),
      when = { { to = "off", absent_for = 60 } },
    },
  }),
}

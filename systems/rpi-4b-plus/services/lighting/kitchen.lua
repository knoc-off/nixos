-- On at the sun's level while someone is about; off five minutes after the
-- sensor last saw anyone, fading over a minute. The plug is not a light:
-- it is left to whoever switches it (devices.nix keeps it out of the room).
room{
  presence = { "kitchen_motion" },
  default = "auto",
  start = "off",
  states = scenes("auto", {
    off = {
      hidden = true,
      look = { on = false, transition = 60 },
      on = { present = "resume" },
    },
    auto = {
      look = sunlight(),
      when = { { to = "off", absent_for = 300 } },
    },
  }),
}

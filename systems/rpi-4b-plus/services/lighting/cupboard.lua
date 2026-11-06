-- On at the sun's level while the door is open, however long; off when it
-- shuts. Shutting also ends any manual change (nothing is remembered).
room{
  doors = { door = "cupboard_door" },
  default = "auto",
  start = "shut",
  forget_after = 0,
  states = scenes("auto", {
    shut = {
      hidden = true,
      look = { on = false, transition = 1 },
      on = { ["door.open"] = "resume" },
    },
    auto = {
      look = sunlight(),
      on = { ["door.closed"] = "shut" },
    },
  }),
}

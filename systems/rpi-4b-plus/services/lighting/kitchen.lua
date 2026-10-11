follow{
  lights = { "light" },
  when = occupancy{ sensors = { "kitchen_motion" }, hold = 300 },
  fade = 60,
}
-- The plug is not a light: left to whoever switches it.

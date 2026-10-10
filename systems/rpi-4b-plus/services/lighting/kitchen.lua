-- The kitchen sensor reports `presence`; it also drives the cat doorbell.
follow{
  lights = { "light" },
  when = occupancy{ sensors = { "kitchen_motion" }, hold = 120 },
  fade = 60,
}
-- The plug is not a light: left to whoever switches it.

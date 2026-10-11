-- kitchen_motion reports `presence` and also drives the cat doorbell;
-- kitchen_motion_2 is a PIR.
follow{
  lights = { "light" },
  when = occupancy{ sensors = { "kitchen_motion", "kitchen_motion_2" }, hold = 300 },
  fade = 60,
}
-- The plug is not a light: left to whoever switches it.

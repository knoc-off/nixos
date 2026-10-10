follow{
  when = occupancy{ sensors = { "hallway_motion" }, hold = 60 },
  fade = 30,
}

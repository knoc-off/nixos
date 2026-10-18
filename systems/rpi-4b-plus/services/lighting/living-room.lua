-- Ceiling light and bulbs follow presence and the sun; the three lamp plugs
-- switch with daylight. Long hold: people sit still here, and mmWave can
-- briefly lose someone on the sofa.
follow{
  lights = { "light", "bulb_1", "bulb_2" },
  when = occupancy{ sensors = { "livingroom_presence" }, hold = 600 },
  fade = 60,
}
sun_switch{ lights = { "carla_desk_lamp", "standing_lamp", "niko_desk_lamp" } }

-- Single toggles the ceiling light; double or hold the whole room.
local room = { "light", "bulb_1", "bulb_2", "carla_desk_lamp", "standing_lamp", "niko_desk_lamp" }
button("livingroom_button", {
  single = toggle{ "light" },
  double = toggle(room),
  hold = toggle(room),
})

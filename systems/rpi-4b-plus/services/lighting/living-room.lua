-- Ceiling light and bulbs follow presence and the sun; the two lamp plugs
-- switch with daylight. Off 30 minutes after the sensor last saw anyone by
-- day (people sit still here, and mmWave loses someone on the sofa), 2
-- minutes at night.
follow{
  lights = { "light", "bulb_1", "bulb_2" },
  when = occupancy{
    sensors = { "livingroom_presence" },
    hold = function() return between(22, 8) and 120 or 1800 end,
  },
  fade = 60,
}
sun_switch{ lights = { "carla_desk_lamp", "standing_lamp" } }

-- Single toggles the ceiling light; double or hold the whole room.
local room = { "light", "bulb_1", "bulb_2", "carla_desk_lamp", "standing_lamp" }
button("livingroom_button", {
  single = toggle{ "light" },
  double = toggle(room),
  hold = toggle(room),
})

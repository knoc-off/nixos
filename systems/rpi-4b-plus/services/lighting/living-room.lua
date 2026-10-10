-- Ceiling light and three lamp plugs. No occupancy sensor yet: the light
-- follows the sun while on, the plugs switch with daylight.
follow{ lights = { "light", "bulb_1", "bulb_2" } }
sun_switch{ lights = { "carla_desk_lamp", "standing_lamp", "niko_desk_lamp" } }

-- Single toggles the ceiling light; double or hold the whole room.
local room = { "light", "bulb_1", "bulb_2", "carla_desk_lamp", "standing_lamp", "niko_desk_lamp" }
button("livingroom_button", {
  single = toggle{ "light" },
  double = toggle(room),
  hold = toggle(room),
})

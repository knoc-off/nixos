-- Ceiling light and bulbs follow presence and the sun; the two lamp plugs
-- switch with daylight whether anyone is here or not. Off 30 minutes after
-- the sensor last saw anyone by day (people sit still here, and mmWave
-- loses someone on the sofa), 2 minutes at night.
--
-- Button: single toggles the ceiling light, double or hold the whole room.
local lamps = { carla_desk_lamp = sun_switch(), standing_lamp = sun_switch() }
local everything = { "light", "bulb_1", "bulb_2", "carla_desk_lamp", "standing_lamp" }

local function with_buttons(on)
  on["button.single"] = { toggle = { "light" } }
  on["button.double"] = { toggle = everything }
  on["button.hold"] = { toggle = everything }
  return on
end

room{
  presence = { "livingroom_presence" },
  buttons = { button = "livingroom_button" },
  default = "auto",
  start = "off",
  states = scenes("auto", {
    off = {
      hidden = true,
      look = { on = false, transition = 60 },
      per_light = lamps,
      on = with_buttons{ present = "resume" },
    },
    auto = {
      look = sunlight(),
      per_light = lamps,
      on = with_buttons{},
      when = {
        { to = "off", absent_for = 1800 },
        { to = "off", absent_for = 120, between = { 22, 8 } },
      },
    },
  }),
}

-- Ceiling light and bulbs follow presence and the sun; the two lamp plugs
-- switch with daylight whether anyone is here or not. Off 30 minutes after
-- the sensor last saw anyone (people sit still here, and mmWave loses
-- someone on the sofa). While the house sleeps: dim and warm, lamps off, off
-- two minutes after.
--
-- Button: single toggles the ceiling light, double or hold the whole room.
local function awake(c) return c.house ~= "night" end
local lamp = sun_switch().on
local function lamp_on(c) return awake(c) and lamp(c) end
local lamps = { carla_desk_lamp = { on = lamp_on }, standing_lamp = { on = lamp_on } }
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
  states = {
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
      when = { { to = "off", absent_for = 1800 }, { to = "night", house = "night" } },
    },
    night = {
      hidden = true,
      forget = true, -- the morning starts afresh, not with last evening's changes
      look = { brightness = 25, color_temp = 454, transition = 1 },
      per_light = { carla_desk_lamp = { on = false }, standing_lamp = { on = false } },
      on = with_buttons{},
      when = { { to = "resume", test = awake }, { to = "off", absent_for = 120 } },
    },
  },
}

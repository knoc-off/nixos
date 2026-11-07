-- Opening the door turns the light on straight away; the presence sensor
-- keeps it on while someone is in there, door shut or not. Off 30 seconds
-- after the sensor last saw anyone (a minute for a door-only visit nobody
-- was seen in), or 3 seconds after the door shuts with nobody detected.
-- While the house sleeps, the same but dim and warm.
local function awake(c) return c.house ~= "night" end

room{
  presence = { "bathroom_presence" },
  doors = { door = "bathroom_door" },
  default = "auto",
  start = "off",
  states = {
    off = {
      hidden = true,
      look = { on = false, transition = 20 },
      on = { present = "resume", ["door.open"] = "resume" },
    },
    auto = {
      look = sunlight(),
      on = { ["door.closed"] = { to = "closing", present = false } },
      when = {
        { to = "off", absent_for = 30, time_in_state = 60 },
        { to = "night", house = "night" },
      },
    },
    night = {
      hidden = true,
      extends = "auto",
      look = { brightness = 20, color_temp = 454, transition = 1 },
      when = { { to = "resume", test = awake } },
    },
    -- No look: the lights stay as they are while the sensor gets a chance
    -- to spot someone who just shut themselves in.
    closing = {
      hidden = true,
      on = { ["door.open"] = "resume" },
      when = {
        { to = "resume", present = true },
        { to = "off", time_in_state = 3 },
      },
    },
  },
}

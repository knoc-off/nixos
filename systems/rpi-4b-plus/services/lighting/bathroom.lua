-- Opening the door turns the light on straight away; the presence sensor
-- keeps it on while someone is in there, door shut or not.
follow{
  when = occupancy{
    sensors = { "bathroom_presence" },
    doors = { "bathroom_door" },
    hold = 30,
    door_hold = 60,
  },
  fade = 20,
}

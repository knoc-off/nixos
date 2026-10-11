-- Opening the door turns the light on straight away; the presence sensor
-- keeps it on while someone is in there, door shut or not. Shutting the door
-- with nobody detected turns it off after 3 seconds.
follow{
  when = occupancy{
    sensors = { "bathroom_presence" },
    doors = { "bathroom_door" },
    hold = 30,
    door_hold = 60,
    close_grace = 3,
  },
  fade = 20,
}

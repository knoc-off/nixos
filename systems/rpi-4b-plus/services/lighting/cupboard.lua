-- On while the door is open, however long, at the sun's level; off when it
-- shuts. Shutting also ends any manual change.
local bulb = light("bulb")
local open = false

local function update()
  if not automatic() then return end
  local t = curve_target("bulb")
  t.on = open
  t.transition = open and 0.4 or 1
  bulb:auto(t)
end

on("cupboard_door", function(p)
  if type(p) ~= "table" or p.contact == nil then return end
  open = not p.contact
  if not automatic() then return end
  if not open then bulb:release({ transition = 1 }) end
  update()
end)

sun_curve()
watch_room(update)
every(30, update)
update()

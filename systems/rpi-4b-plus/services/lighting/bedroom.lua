-- The light follows the sun while on and ramps up on the fixed-clock wake
-- schedule (HA "Sunrise ..." settings). Walking in switches it on, except
-- 22:00-08:00; it goes off two minutes after the sensor last saw anyone.
local names = { "light", "bulb_1" }
follow{
  lights = names,
  wake = wake_ramp(),
  when = occupancy{ sensors = { "bedroom_presence" }, hold = 120 },
  fade = 30,
  quiet = { 22, 8 },
}

local LOW = 25 -- of 254
local evening = function()
  local h = clock()
  return h >= 21 or h < 6
end
local function dim()
  for _, n in ipairs(names) do
    local s = light(n):state()
    if s and s.on and s.brightness > LOW + 10 then return false end
  end
  return true
end

-- Bedtime button. Single: on -> (dim, or day) off, else low; off -> low in
-- the evening, curve by day. Hold: low now, off after five minutes.
local off_timer
local function low() set(names, { brightness = LOW, transition = 0.4 }) end
local function off() set(names, { on = false, transition = 0.4 }) end

button("bedroom_button", {
  single = function()
    if off_timer then cancel(off_timer); off_timer = nil end
    if any_on(names) then
      if dim() or not evening() then off() else low() end
    elseif evening() then
      low()
    else
      set(names, "curve")
    end
  end,
  hold = function()
    if off_timer then cancel(off_timer) end
    low()
    off_timer = after(300, function()
      off_timer = nil
      off()
    end)
  end,
})

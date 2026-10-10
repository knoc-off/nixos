-- Helpers every room script can use, loaded before it in the same sandbox.
-- Everything here is built on the public API in script.rs; a room that
-- wants something else just writes it.

local function clamp(x, lo, hi)
  return math.max(lo, math.min(hi, x))
end

local function each(names, f)
  for _, n in ipairs(names or lights) do
    f(n)
  end
end

-- A value HA controls through a retained MQTT topic, as a getter. Payloads
-- that don't parse as the default's type are ignored. Top level only, like
-- on_topic.
function setting(topic, default)
  local value = default
  on_topic(topic, function(p)
    local v
    if type(default) == "number" then
      v = tonumber(p)
    elseif type(default) == "boolean" then
      if p == true or p == "true" or p == "on" then
        v = true
      elseif p == false or p == "false" or p == "off" then
        v = false
      end
    elseif type(p) == type(default) then
      v = p
    end
    if v ~= nil then
      value = v
    end
  end)
  return function()
    return value
  end
end

-- Bulb -> function returning what the sun says for it right now.
local curves = {}
local ct_enabled

-- Give `names` (default: all) a sun curve, on the HA sun-follow sliders,
-- kept on their old topics so existing values carry over. follow() does
-- this itself; a room driving its bulbs by hand calls it to use
-- curve_target(). Top level only.
function sun_curve(names)
  ct_enabled = ct_enabled or setting("mqtt-auto/color-temp-cycle/enabled", true)
  each(names, function(n)
    if curves[n] then return end
    local base = "mqtt-auto/sun-follow/" .. light(n):device() .. "/"
    local min = setting(base .. "min-brightness", 5)
    local max = setting(base .. "max-brightness", 100)
    local gamma = setting(base .. "gamma", 1)
    curves[n] = function()
      return {
        brightness = sun.level({
          min = clamp(min(), 0, 100),
          max = clamp(max(), 0, 100),
          gamma = clamp(gamma(), 0.1, 10),
        }),
        color_temp = ct_enabled() and sun.ct() or nil,
      }
    end
  end)
end

-- `name` on at its sun level and colour, or full brightness without a
-- curve (plugs).
function curve_target(name)
  local t = curves[name] and curves[name]() or {}
  return { on = true, brightness = t.brightness, color_temp = t.color_temp }
end

-- Bulbs follow the sun's brightness and colour temperature. Options:
--   lights: names (default: all of the room's)
--   when:   an occupancy(): on while occupied, released and faded off when
--           it empties. Without it the automation never switches the bulbs
--           on or off, it only shapes them while they are on.
--   fade:   seconds to fade out once the room empties (default 60)
--   wake:   a wake_ramp(), which switches the bulbs on and ramps them up
function follow(opts)
  opts = opts or {}
  local names = opts.lights or lights
  local occ, wake = opts.when, opts.wake
  local fade = opts.fade or 60
  sun_curve(names)

  local waking = false
  local function update(transition)
    local ramp = wake and wake.level()
    -- The ramp starting is a new instruction: a manual off from the night
    -- before must not keep the room dark.
    if ramp and not waking then
      each(names, function(n) light(n):release() end)
    end
    -- Ramp over: stay where it ended rather than jump to the curve. The hold
    -- ends by itself once the curve comes back down to it in the evening.
    if waking and not ramp then
      each(names, function(n)
        local s = light(n):state()
        if s and s.on and s.mode == "auto" then
          light(n):user({ brightness = s.brightness, color_temp = s.color_temp })
        end
      end)
    end
    waking = ramp ~= nil
    each(names, function(n)
      local t = curve_target(n)
      local s = light(n):state()
      if ramp then
        t.brightness = ramp
      elseif occ then
        t.on = occ.occupied
      else
        t.on = s ~= nil and s.on
      end
      t.transition = transition or 2
      light(n):auto(t)
      -- Off by hand where the automation would leave it off anyway: nothing
      -- to hold, and the state topic shouldn't say "held".
      if not occ and not ramp and s and s.mode == "held" and not s.on then
        light(n):release()
      end
    end)
  end

  if occ then
    occ.watch(function(occupied)
      if not occupied then
        -- A manual change lasts as long as the visit.
        each(names, function(n) light(n):release({ transition = fade }) end)
      end
      update(occupied and 0.4 or fade)
    end)
  end
  every(30, function() update() end)
  update(0.4)
end

-- Whether anyone is in the room. Options:
--   sensors:   devices reporting `occupancy` (or `presence`); occupied while
--              any says so, and for `hold` seconds after it clears
--   doors:     contact sensors; opening one counts as someone there for
--              `door_hold` seconds, until a sensor picks them up
--   hold:      default 60
--   door_hold: default 120
-- Starts vacant: after a restart the first motion turns the lights on, and a
-- light someone left on is held until the next visit ends.
function occupancy(opts)
  local hold, door_hold = opts.hold or 60, opts.door_hold or 120
  local self = { occupied = false }
  local watchers, active, timers = {}, {}, {}

  function self.watch(f)
    table.insert(watchers, f)
  end

  local function evaluate()
    local now = next(active) ~= nil or next(timers) ~= nil
    if now ~= self.occupied then
      self.occupied = now
      log(now and "occupied" or "vacant")
      for _, f in ipairs(watchers) do
        f(now)
      end
    end
  end

  local function stop(dev)
    if timers[dev] then
      cancel(timers[dev])
      timers[dev] = nil
    end
  end

  local function evidence(dev, secs)
    stop(dev)
    timers[dev] = after(secs, function()
      timers[dev] = nil
      evaluate()
    end)
  end

  for _, dev in ipairs(opts.sensors or {}) do
    on(dev, function(p)
      if type(p) ~= "table" then return end
      local v = p.occupancy
      if v == nil then v = p.presence end
      if type(v) ~= "boolean" then return end
      if v then
        active[dev] = true
        stop(dev)
      elseif active[dev] then
        active[dev] = nil
        evidence(dev, hold)
      end
      evaluate()
    end)
  end
  for _, dev in ipairs(opts.doors or {}) do
    on(dev, function(p)
      -- z2m: `contact = true` is closed.
      if type(p) == "table" and p.contact == false then
        evidence(dev, door_hold)
        evaluate()
      end
    end)
  end
  return self
end

-- Plugs switched by daylight, on the HA threshold/invert knobs: on above
-- `threshold`% daylight (below, inverted), with a 5% deadband so it can't
-- flap. Each crossing releases the plug: a new part of the day overrides a
-- manual switch from the last one.
function sun_switch(opts)
  each(opts.lights, function(n)
    local base = "mqtt-auto/sun-follow/" .. light(n):device() .. "/"
    local threshold = setting(base .. "threshold", 15)
    local invert = setting(base .. "invert", false)
    local last
    local function update()
      local frac = sun.daylight()
      if invert() then frac = 1 - frac end
      local t = clamp(threshold(), 0, 100) / 100
      local want = last
      if frac >= t + 0.05 then
        want = true
      elseif frac <= t - 0.05 or want == nil then
        want = false
      end
      if last ~= nil and want ~= last then
        light(n):release()
      end
      last = want
      light(n):auto({ on = want })
    end
    every(30, update)
    update()
  end)
end

-- A fixed-clock wake-up ramp on the HA sunrise settings. Deliberately not
-- the real sun: that would mean a 9 hour ramp from 03:50 in June.
function wake_ramp()
  local base = "mqtt-auto/sunrise-lights/"
  local at = setting(base .. "start-time", "06:30:00")
  local minutes = setting(base .. "duration", 45)
  local max = setting(base .. "max-brightness", 30)
  local gamma = setting(base .. "gamma", 2.2)
  return {
    -- Brightness for now, or nil outside the ramp.
    level = function()
      local h, m = tostring(at()):match("^(%d+):(%d+)")
      local total = minutes()
      if not h or total <= 0 then return nil end
      local start = tonumber(h) + tonumber(m) / 60
      local elapsed = (clock() - start) % 24 * 60
      if elapsed >= total then return nil end
      local t = elapsed / total
      -- Smoothstep, then gamma to spend longer at the dim end.
      local r = (t * t * (3 - 2 * t)) ^ clamp(gamma(), 0.1, 10)
      return math.max(1, math.floor(r * clamp(max(), 0, 100) / 100 * 254 + 0.5))
    end,
  }
end

-- Map a button's z2m actions to functions.
function button(device, actions)
  on_topic("zigbee2mqtt/" .. device .. "/action", function(p)
    local a = type(p) == "table" and p.action or p
    local f = type(a) == "string" and actions[a]
    if f then f() end
  end)
end

-- Is any of `names` on?
function any_on(names)
  local found = false
  each(names, function(n)
    local s = light(n):state()
    if s and s.on then found = true end
  end)
  return found
end

-- A person's choice for `names`: `t` is a light:user() table, or "curve"
-- for on at the sun's level.
function set(names, t)
  each(names, function(n)
    local target = t
    if t == "curve" then
      target = curve_target(n)
      target.transition = 0.4
    end
    light(n):user(target)
  end)
end

-- Button action: anything on -> all off, otherwise all on at the curve.
function toggle(names)
  return function()
    if any_on(names) then
      set(names, { on = false, transition = 0.4 })
    else
      set(names, "curve")
    end
  end
end

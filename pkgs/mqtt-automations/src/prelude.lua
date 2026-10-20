-- Helpers every room script can use, loaded before it in the same sandbox.
-- Everything here is built on the public API in script.rs; a room that
-- wants something else just writes it.

local function clamp(x, lo, hi)
  return math.max(lo, math.min(hi, x))
end

-- Is the time of day in [from, to) hours? Wraps past midnight ({ 22, 8 }).
function between(from, to)
  local h = clock()
  if from <= to then return h >= from and h < to end
  return h >= from or h < to
end

local function each(names, f)
  for _, n in ipairs(names or lights) do
    f(n)
  end
end

-- A value HA controls through a retained MQTT topic, as a getter. Payloads
-- that don't parse as the default's type are ignored. `changed`, if given,
-- runs after each new value. Top level only, like on_topic. The second
-- return value sets it locally (for a reset that also publishes it).
function setting(topic, default, changed)
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
      if changed then changed(v) end
    end
  end)
  return function()
    return value
  end, function(v)
    value = v
  end
end

-- Room controls from HA, on `lights/<room>/...`:
--   scene:     "auto" follows the sun; "bright", "dim" and "night" replace
--              its brightness (and colour, for night) without holding the
--              bulbs, so they still switch on and off by themselves. Lasts
--              until the room has been empty for follow{}'s `reset_after`.
--   automatic: false leaves the bulbs entirely alone: no switching, no sun
--              shaping, no wake ramp. Buttons still work.
--   release:   reset: every bulb back to the automation, scene back to
--              "auto", remembered settings forgotten, automatic back on.
-- `lights/automatic` and `lights/release` do the same for the whole house;
-- a room runs only while both its own and the house switch are on.
local SCENES = {
  bright = { brightness = 254 },
  dim = { brightness = 76 },
  night = { brightness = 8, color_temp = 454 },
}
local room_watchers, reset_watchers = {}, {}
local function room_changed()
  for _, f in ipairs(room_watchers) do f() end
end
local scene_name = "auto"
-- Retained back, so HA shows the scene in use after a restart too; our own
-- echo arrives unchanged and stops there.
local function use_scene(name)
  if name ~= "auto" and not SCENES[name] then return end
  if name ~= scene_name then
    scene_name = name
    publish("scene", name)
    room_changed()
  end
end
on_topic("lights/" .. room .. "/scene", use_scene)
local room_auto, set_room_auto = setting("lights/" .. room .. "/automatic", true, room_changed)
local house_auto, set_house_auto = setting("lights/automatic", true, room_changed)
function automatic()
  return room_auto() and house_auto()
end

-- Back to "auto".
function end_scene()
  use_scene("auto")
end

local function reset(house)
  each(lights, function(n) light(n):release() end)
  end_scene()
  for _, f in ipairs(reset_watchers) do f() end
  set_room_auto(true)
  publish("automatic", true)
  if house then
    set_house_auto(true)
    publish_house("automatic", true)
  end
  room_changed()
end
on_topic("lights/" .. room .. "/release", function() reset(false) end)
on_topic("lights/release", function() reset(true) end)

-- Run `f` whenever a room control changes, so the bulbs follow at once.
function watch_room(f)
  table.insert(room_watchers, f)
end

-- Run `f` on a room or house reset, to drop whatever the room remembers.
function on_reset(f)
  table.insert(reset_watchers, f)
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
-- curve (plugs). The room's scene, if any, replaces the curve's values.
function curve_target(name)
  local t = curves[name] and curves[name]() or {}
  local s = SCENES[scene_name]
  if s and curves[name] then
    t.brightness = s.brightness
    t.color_temp = s.color_temp or t.color_temp
  end
  return { on = true, brightness = t.brightness, color_temp = t.color_temp }
end

-- Bulbs follow the sun's brightness and colour temperature. Options:
--   lights: names (default: all of the room's)
--   when:   an occupancy(): on while occupied, faded off when it empties.
--           Without it the automation never switches the bulbs on or off,
--           it only shapes them while they are on.
--   fade:   seconds to fade out once the room empties (default 60)
--   reset_after: seconds the room must stay empty before the scene and any
--           manual setting (a brightness, a colour, an off) are forgotten
--           (default 3600). Coming back sooner restores them as left.
--   wake:   a wake_ramp(), which switches the bulbs on and ramps them up
--   quiet:  { from, to } hours (e.g. { 22, 8 }): arriving in this window
--           does not switch the bulbs on. Only arrival counts, so lights
--           already on stay on into it and nothing switches on at its end.
--           The wake ramp and buttons are unaffected.
function follow(opts)
  opts = opts or {}
  local names = opts.lights or lights
  local occ, wake, quiet = opts.when, opts.wake, opts.quiet
  local fade = opts.fade or 60
  local reset_after = opts.reset_after or 3600
  sun_curve(names)

  local function quiet_now()
    return quiet ~= nil and between(quiet[1], quiet[2])
  end

  -- Whether this visit switched the bulbs on.
  local lit = false
  -- Manual settings the room had when it emptied, by bulb, and the timer
  -- that forgets them (and the scene).
  local remembered, forget_timer = {}, nil
  -- Holds the wake ramp made itself, by bulb (brightness): not a person's
  -- choice, so not worth remembering.
  local ramp_held = {}

  local function forget()
    if forget_timer then cancel(forget_timer) end
    forget_timer, remembered, ramp_held = nil, {}, {}
  end
  on_reset(forget)

  local waking = false
  local function update(transition)
    -- Automations off: hands off entirely.
    if not automatic() then return end
    local ramp = wake and wake.level()
    -- The ramp starting is a new instruction: a manual off from the night
    -- before must not keep the room dark.
    if ramp and not waking then
      each(names, function(n) light(n):release() end)
    end
    -- Ramp over: stay where it ended rather than jump to the curve, until
    -- the room empties.
    if waking and not ramp then
      each(names, function(n)
        local s = light(n):state()
        if s and s.on and s.mode == "auto" then
          light(n):user({ brightness = s.brightness, color_temp = s.color_temp })
          ramp_held[n] = s.brightness
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
        t.on = lit
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
      lit = occupied and not quiet_now()
      if not automatic() then return end
      -- A wake ramp ignores occupancy, so releasing during it would undo a
      -- manual off the moment the sensor loses someone lying in bed.
      if not (wake and wake.level()) then
        if occupied then
          if forget_timer then cancel(forget_timer) end
          forget_timer = nil
        end
        each(names, function(n)
          local s = light(n):state()
          if not occupied then
            -- Remember a person's setting, then fade out like the rest.
            local by_ramp = ramp_held[n] and s and math.abs(s.brightness - ramp_held[n]) <= 5
            if s and s.mode == "held" and not by_ramp then
              remembered[n] = { on = s.on, brightness = s.brightness, color_temp = s.color_temp }
            end
            light(n):release({ transition = fade })
          elseif remembered[n] then
            light(n):user({
              on = remembered[n].on,
              brightness = remembered[n].brightness,
              color_temp = remembered[n].color_temp,
              transition = 0.4,
            })
          elseif s and s.mode == "held" and not s.on then
            -- Held off from while the room was empty (a report misread
            -- during the fade-out): walking in means light. Held on (the
            -- wall switch, say) is kept.
            light(n):release()
          end
        end)
        if occupied then
          remembered = {}
        else
          ramp_held = {}
          forget_timer = after(reset_after, function()
            forget_timer, remembered = nil, {}
            end_scene()
          end)
        end
      end
      update(occupied and 0.4 or fade)
    end)
    -- Switched back to automatic: catch up with whether anyone is there.
    watch_room(function() lit = occ.occupied and not quiet_now() end)
  end
  watch_room(function() update(0.4) end)
  every(30, function() update() end)
  update(0.4)
end

-- Whether anyone is in the room. Options:
--   sensors:   devices reporting `occupancy` (or `presence`); occupied while
--              any says so, and for `hold` seconds after it clears
--   doors:     contact sensors; opening one counts as someone there for
--              `door_hold` seconds, until a sensor picks them up; shutting
--              one with no sensor active empties the room after
--              `close_grace` seconds
--   hold:      seconds, or a function returning them, asked each time a
--              sensor clears (e.g. shorter at night); default 60
--   door_hold: default 120
--   close_grace: default 3
-- Starts vacant: after a restart the first motion turns the lights on, and a
-- light someone left on is held until the next visit ends.
function occupancy(opts)
  local hold_opt, door_hold = opts.hold or 60, opts.door_hold or 120
  local function hold()
    if type(hold_opt) == "function" then return hold_opt() end
    return hold_opt
  end
  local close_grace = opts.close_grace or 3
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
      publish("occupied", now)
      for _, f in ipairs(watchers) do
        f(now)
      end
    end
  end
  publish("occupied", false)

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
        evidence(dev, hold())
      end
      evaluate()
    end)
  end
  for _, dev in ipairs(opts.doors or {}) do
    on(dev, function(p)
      if type(p) ~= "table" or type(p.contact) ~= "boolean" then return end
      -- z2m: `contact = true` is closed.
      if not p.contact then
        evidence(dev, door_hold)
      else
        -- Shut with nobody detected: empty after a short grace, for a
        -- sensor that hasn't spotted someone who just walked in. Sensors
        -- that still see someone keep the room occupied; ones counting
        -- down their hold (someone just left) are cut short too. Only
        -- shortens: a door shutting on an empty room lights nothing.
        if timers[dev] then evidence(dev, close_grace) end
        for _, s in ipairs(opts.sensors or {}) do
          if timers[s] then evidence(s, close_grace) end
        end
      end
      evaluate()
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
      if not automatic() then return end
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
    watch_room(update)
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

-- Match the TV output to the video while it plays, restore afterwards:
--  * refresh rate: at a fixed 60 Hz, 24/25 fps content judders (3:2 and 2.4
--    pulldown) and mpv's interpolation ghosts high-contrast motion instead of
--    fixing it, so switch the mode like every TV box does.
--  * HDR: PQ/HLG video switches the output to 10-bit + cm "hdr" so the TV gets
--    a real HDR10 signal. Hyprland 0.56's render:cm_auto_hdr did not do this
--    on its own here. SDR video and the desktop stay 8-bit sRGB, since SDR
--    mapped into HDR mode looks dimmer/flatter.
-- Hyprland on this host uses the Lua config parser, so `hyprctl keyword
-- monitor` is refused; hl.monitor via eval is the supported path. That call
-- merges with the existing rule (omitted bitdepth/cm keep their old values),
-- so every call passes all three.
local utils = require("mp.utils")
local hyprctl = "@hyprctl@"
local orig -- output state to restore, set on first switch

local function run(args)
	local r = mp.command_native({
		name = "subprocess",
		args = args,
		capture_stdout = true,
		playback_only = false,
	})
	return r.status == 0 and r.stdout or nil
end

local function monitor()
	local out = run({ hyprctl, "-j", "monitors" })
	local list = out and utils.parse_json(out)
	if not list then
		return nil
	end
	for _, m in ipairs(list) do
		if m.focused then
			return m
		end
	end
	return list[1]
end

-- The monitor's current output as { rate, bitdepth, cm }.
local function current(m)
	return {
		rate = m.refreshRate,
		bitdepth = (m.currentFormat or ""):find("2101010") and 10 or 8,
		cm = m.colorManagementPreset or "srgb",
	}
end

local function same(a, b)
	-- availableModes rounds to 2 decimals while refreshRate is exact, so a
	-- tolerance; tighter than the 0.02 gap between 23.98 and 24.00.
	return math.abs(a.rate - b.rate) < 0.015 and a.bitdepth == b.bitdepth and a.cm == b.cm
end

local function apply(m, s)
	run({
		hyprctl,
		"eval",
		string.format(
			'hl.monitor({ output = %q, mode = "%dx%d@%.2f", position = "%dx%d", scale = %s, bitdepth = %d, cm = %q })',
			m.name, m.width, m.height, s.rate, m.x, m.y, m.scale, s.bitdepth, s.cm
		),
	})
end

-- Smallest integer multiple of fps that is >= 48 Hz and offered at the
-- current resolution (25 -> 50, 29.97 -> 59.94), else fps itself (24 -> 24,
-- 23.976 -> 23.98), else nil.
local function pick(fps, m)
	local rates = {}
	for _, s in ipairs(m.availableModes or {}) do
		local w, h, r = s:match("^(%d+)x(%d+)@([%d%.]+)Hz$")
		if tonumber(w) == m.width and tonumber(h) == m.height then
			rates[#rates + 1] = tonumber(r)
		end
	end
	-- Closest offered rate, not the first within tolerance: 23.976 fps must
	-- get 23.98 Hz, not 24.00 (a dropped frame every ~40 s).
	local function has(t)
		local best
		for _, r in ipairs(rates) do
			if math.abs(r - t) < 0.05 and (not best or math.abs(r - t) < math.abs(best - t)) then
				best = r
			end
		end
		return best
	end
	for k = 1, 3 do
		local t = fps * k
		if t >= 48 and has(t) then
			return has(t)
		end
	end
	return has(fps)
end

local function restore()
	if not orig then
		return
	end
	local m = monitor()
	if m and not same(current(m), orig) then
		apply(m, orig)
	end
	orig = nil
end

mp.observe_property("video-params", "native", function(_, p)
	if not p then
		restore()
		return
	end
	local m = monitor()
	if not m then
		return
	end
	local now = current(m)
	local base = orig or now
	local fps = mp.get_property_number("container-fps")
	-- The embedded libmpv (jellyfin-desktop) renders into a Qt sRGB surface
	-- and tone-maps itself, so HDR output would only wash it out.
	local hdr = (p.gamma == "pq" or p.gamma == "hlg") and not (mp.get_property("vo") or ""):find("libmpv")
	local want = {
		rate = fps and pick(fps, m) or base.rate,
		bitdepth = hdr and 10 or base.bitdepth,
		cm = hdr and "hdr" or base.cm,
	}
	if same(now, want) then
		return
	end
	orig = base
	apply(m, want)
	mp.osd_message(string.format("%.2f fps -> %.2f Hz%s", fps or 0, want.rate, hdr and " HDR" or ""), 2)
end)

mp.register_event("shutdown", restore)

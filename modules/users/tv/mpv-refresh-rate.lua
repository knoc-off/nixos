-- Match the TV refresh rate to the video while it plays, restore afterwards.
-- At a fixed 60 Hz, 24/25 fps content judders (3:2 and 2.4 pulldown) and
-- mpv's interpolation ghosts high-contrast motion instead of fixing it; every
-- TV box switches the output mode instead. Hyprland on this host uses the Lua
-- config parser, so `hyprctl keyword monitor` is refused; hl.monitor via eval
-- is the supported path.
local utils = require("mp.utils")
local hyprctl = "@hyprctl@"
local orig -- mode string to restore, set on first switch

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

local function mode(m, rate)
	return string.format("%dx%d@%.2f", m.width, m.height, rate)
end

local function setmode(m, s)
	run({
		hyprctl,
		"eval",
		string.format('hl.monitor({ output = %q, mode = %q, position = "%dx%d", scale = %s })', m.name, s, m.x, m.y, m.scale),
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
	local function has(t)
		for _, r in ipairs(rates) do
			if math.abs(r - t) < 0.05 then
				return r
			end
		end
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
	if m and mode(m, m.refreshRate) ~= orig then
		setmode(m, orig)
	end
	orig = nil
end

mp.observe_property("container-fps", "number", function(_, fps)
	if not fps then
		restore()
		return
	end
	local m = monitor()
	if not m then
		return
	end
	local target = pick(fps, m)
	if not target or math.abs(m.refreshRate - target) < 0.05 then
		return
	end
	orig = orig or mode(m, m.refreshRate)
	setmode(m, mode(m, target))
	mp.osd_message(string.format("%.2f fps -> %.2f Hz", fps, target), 2)
end)

mp.register_event("shutdown", restore)

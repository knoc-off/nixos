local env = require("nix-env")
local mainMod = "SUPER"

-- Plugins
-- hl.plugin.load(env.kinetic_scroll_so) -- disabled: crashes with Hyprland 0.55.2
if env.confined_floats_so then
	hl.plugin.load(env.confined_floats_so)
end
if env.scroll_overview_so then
	hl.plugin.load(env.scroll_overview_so)
end

-- Monitors
hl.monitor({ output = "eDP-1", mode = "preferred", position = "0x0", scale = env.display_scale })
hl.monitor({ output = "", mode = "preferred", position = "auto-center-up", scale = 1 })

-- Config
hl.config({
	ecosystem = {
		no_update_news = true,
	},

	general = {
		layout = "scrolling",
		gaps_out = { top = 10, right = 30, bottom = 10, left = 10 },
	},

	scrolling = {
		direction = "right",
		column_width = 0.5,
	},

	cursor = {
		warp_on_change_workspace = true,
	},

	gestures = {
		scrolling = {
			move_snap_to_grid = true,
			move_snap_cursor = true,
		},
	},

	misc = {
		disable_hyprland_logo = true,
		force_default_wallpaper = 0,
		focus_on_activate = true,
	},

	decoration = {
		rounding = 6,
		blur = {
			enabled = true,
			size = 5,
			passes = 2,
		},
	},

	animations = {
		enabled = true,
	},

	input = {
		follow_mouse = 1,
		repeat_rate = 25,
		repeat_delay = 200,
		touchpad = {
			natural_scroll = true,
			tap_to_click = true,
			middle_button_emulation = true,
			scroll_factor = 0.25,
		},
	},
})

-- Curves & animations
hl.curve("snap", { type = "bezier", points = { { 0.2, 1 }, { 0.3, 1 } } })
hl.curve("smooth", { type = "bezier", points = { { 0.25, 0.8 }, { 0.25, 1 } } })

hl.animation({ leaf = "global", enabled = true, speed = 2, bezier = "snap" })
hl.animation({ leaf = "windowsMove", enabled = true, speed = 6, bezier = "snap" })
hl.animation({ leaf = "workspaces", enabled = true, speed = 2, bezier = "snap", style = "slidevert" })

-- Device
hl.device({
	name = "logitech-usb-receiver-mouse",
	accel_profile = "flat",
})

-- Gestures
hl.gesture({ fingers = 3, direction = "horizontal", action = "scroll_move", scale = 1.0 })
hl.gesture({ fingers = 3, direction = "vertical", action = "workspace" })
hl.gesture({
	fingers = 4,
	direction = "u",
	action = function()
		if hl.plugin.scrolloverview then
			hl.plugin.scrolloverview.overview("toggle")
		end
	end,
})

-- Window stacking: when a new window stacks into the focused column, stack it
-- onto the lone neighbour AND cancel the spurious viewport slide that 0.55.2's
-- re-fit causes (this version has no inhibit_scroll to suppress it). The anchor
-- window's tape position never changes when something stacks below it, so any
-- change in its on-screen x IS exactly the unwanted offset delta -- and since it
-- all happens in one frame, correcting it leaves zero visible movement. New
-- windows that get their own column are left alone (that shift is wanted).
local pendingAnchor = nil

hl.on("window.open_early", function(w)
	pendingAnchor = nil
	if not w or w.floating then
		return
	end
	local a = hl.get_active_window()
	if not a or a.floating or not a.at then
		return
	end
	pendingAnchor = { win = a, x = a.at.x }
end)

hl.on("window.open", function(window)
	local anchor = pendingAnchor
	pendingAnchor = nil
	if window.floating then
		return
	end

	-- Auto-stack: if the previously focused window is alone in its column,
	-- stack the new window on top of it instead of creating a new column.
	local prev = hl.get_last_window()
	if prev and not prev.floating then
		local pl = prev.layout
		if pl and pl.name == "scrolling" and pl.column and #pl.column.windows == 1 then
			hl.dispatch(hl.dsp.layout("consume_or_expel prev"))
		end
	end

	-- No-shift: only when the new window actually stacked into an existing
	-- column, cancel the offset the re-fit introduced.
	if not anchor then
		return
	end
	local nl = window.layout
	if not nl or nl.name ~= "scrolling" or not nl.column or #nl.column.windows < 2 then
		return
	end
	local at = anchor.win.at
	if not at then
		return
	end
	local delta = at.x - anchor.x
	if delta ~= 0 then
		hl.dispatch(hl.dsp.layout("move " .. -delta))
	end
end)

-- Fraction of a window visible horizontally on its own monitor. Scrolling is
-- horizontal and tiled windows always span the monitor height, so vertical
-- can't clip them. Window .size uses keys x=width, y=height; monitor exposes
-- .x and .width.
local function visibleFraction(w)
	if not w then
		return 0
	end
	local at, sz, mon = w.at, w.size, w.monitor
	if not at or not sz or not mon then
		return 0
	end
	local width = sz.x
	if width <= 0 then
		return 0
	end
	local left = math.max(at.x, mon.x)
	local right = math.min(at.x + width, mon.x + mon.width)
	return (right - left) / width
end

-- hl.dsp.focus warps the cursor to the window's middle (CA::focus ->
-- warpCursor, force=false), which would yank the pointer mid-motion. no_warps
-- honours that for non-forced warps, so force it on just for the redirect and
-- restore the user's value immediately after.
local function focusNoWarp(target)
	local prevNoWarps = hl.get_config("cursor:no_warps")
	hl.config({ cursor = { no_warps = true } })
	hl.dispatch(hl.dsp.focus({ window = target }))
	hl.config({ cursor = { no_warps = prevNoWarps } })
end

-- Bar-hover refocus (1/2): as the cursor moves toward the left noctalia bar it
-- crosses a window that's ~99% off-screen; follow-mouse focuses it
-- (window.active, reason FFM) without scrolling to it. The next click
-- HARD-focuses that active window and yanks the viewport to it. Fix: the moment
-- follow-mouse makes a mostly-off-screen window active, hand focus back to the
-- previous window. Pointer (FFM) only; keyboard nav still scrolls. The later
-- click re-focus emits no window.active (same window), so FFM is the only hook.
local FOCUS_REASON_FFM = 1 -- Desktop::eFocusReason: 0=UNKNOWN 1=FFM 2=KEYBIND ...

hl.on("window.active", function(w, reason)
	if reason ~= FOCUS_REASON_FFM then
		return
	end
	if not w or w.floating or visibleFraction(w) >= 0.1 then -- >10% visible = not "mostly off"
		return
	end
	local prev = hl.get_last_window()
	if not prev then
		return
	end
	focusNoWarp(prev)
end)

-- Bar-hover refocus (2/2): the click-recenter only jumps when the focused
-- window is (mostly) off-screen -- the click hard-focuses it and yanks the
-- viewport over. A fully on-screen window has nothing to chase, so recentering
-- it is a no-op. Watch for the cursor crossing onto a shell region and, on that
-- off->on transition, if the active window isn't fully on-screen, hand focus to
-- one that is. Fires once on entry; once a widget popup (an xdg_popup invisible
-- to get_layers) grabs input the compositor suppresses follow-mouse anyway.
local SHELL_NS = {
	"noctalia-bar-content-",
	"noctalia-bar-trigger-",
	"noctalia-bar-exclusion-",
	"noctalia-popupmenu-",
	"noctalia-dock",
	"noctalia-notifications-",
	"noctalia-osd-",
	"noctalia-toast-",
}
local SHELL_MARGIN = 12 -- px slop so the bar's inner edge doesn't flicker detection

local function matchesAny(ns, set)
	for _, pfx in ipairs(set) do
		if ns:sub(1, #pfx) == pfx then
			return true
		end
	end
	return false
end

local function cursorOnShell()
	local c = hl.get_cursor_pos()
	if not c then
		return false
	end
	for _, ls in ipairs(hl.get_layers()) do
		if
			ls.mapped
			and matchesAny(ls.namespace or "", SHELL_NS)
			and c.x >= ls.x - SHELL_MARGIN
			and c.x < ls.x + ls.w + SHELL_MARGIN
			and c.y >= ls.y - SHELL_MARGIN
			and c.y < ls.y + ls.h + SHELL_MARGIN
		then
			return true
		end
	end
	return false
end

-- Prefer the last-focused window if it's fully on-screen; otherwise any
-- fully-on-screen tiled window on the active workspace. get_windows defaults to
-- mapped=true, and the workspace filter keeps us to the focused monitor's
-- current workspace -- so hidden/other-workspace windows can never be picked.
local function pickOnScreen(active)
	local prev = hl.get_last_window()
	if prev and not prev.floating and prev.visible and prev.address ~= active.address and visibleFraction(prev) >= 0.99 then
		return prev
	end
	local ws = hl.get_active_workspace()
	local cands = ws and hl.get_windows({ floating = false, workspace = ws }) or hl.get_windows({ floating = false })
	for _, w in ipairs(cands) do
		if w.address ~= active.address and visibleFraction(w) >= 0.99 then
			return w
		end
	end
	return nil
end

local wasOnShell = false

hl.timer(function()
	local onShell = cursorOnShell()
	-- Only act on the off->on transition: the moment the cursor first enters a
	-- shell region. While it lingers, do nothing.
	if onShell and not wasOnShell then
		local active = hl.get_active_window()
		if active and not active.floating and visibleFraction(active) < 0.99 then
			local target = pickOnScreen(active)
			if target then
				focusNoWarp(target)
			end
		end
	end
	wasOnShell = onShell
end, { timeout = 50, type = "repeat" })

-- Dropdown terminal (Ghostty)
do
	local drop_class = "com.mitchellh.ghostty-hdrop"
	local drop_ws = "drop_ghostty"

	hl.window_rule({
		match = { class = drop_class },
		float = true,
		size = "monitor_w (monitor_h*0.5)",
		move = "0 0",
		no_max_size = true,
	})

	hl.workspace_rule({
		workspace = "special:" .. drop_ws,
		animation = "slidevert",
	})

	hl.bind(mainMod .. " + grave", function()
		local wins = hl.get_windows({ class = drop_class })
		if #wins == 0 then
			hl.exec_cmd("ghostty --class=" .. drop_class, {
				workspace = "special:" .. drop_ws,
			})
		else
			hl.dispatch(hl.dsp.workspace.toggle_special(drop_ws))
		end
	end)

	hl.on("hyprland.start", function()
		hl.exec_cmd("ghostty --class=" .. drop_class, {
			workspace = "special:" .. drop_ws .. " silent",
		})
	end)
end

-- Workspace rules (smart gaps)
hl.workspace_rule({ workspace = "w[tv1]", gaps_out = 0, gaps_in = 0 })
hl.workspace_rule({ workspace = "f[1]", gaps_out = 0, gaps_in = 0 })

-- Window rules
hl.window_rule({ match = { float = false, workspace = "w[tv1]" }, border_size = 0, rounding = 0 })
hl.window_rule({ match = { float = false, workspace = "f[1]" }, border_size = 0, rounding = 0 })

hl.window_rule({ match = { class = "org.gnome.Calculator" }, float = true })
hl.window_rule({ match = { class = "org.gnome.Settings" }, float = true })
hl.window_rule({ match = { class = "pavucontrol" }, float = true })
hl.window_rule({ match = { class = "nm-connection-editor" }, float = true })
hl.window_rule({ match = { class = "blueberry.py" }, float = true })
hl.window_rule({ match = { class = "xdg-desktop-portal" }, float = true })
hl.window_rule({ match = { class = "xdg-desktop-portal-gnome" }, float = true })
hl.window_rule({ match = { class = "xdg-desktop-portal-hyprland" }, float = true })
hl.window_rule({ match = { class = "org.gnome.Nautilus" }, float = true })

-- FreeCad
hl.window_rule({
	match = { initial_class = "^org\\.freecad\\.FreeCAD$", initial_title = "^Customize$" },
	float = true,
	center = true,
	size = "(monitor_w*0.75) (monitor_h*0.75)",
	no_max_size = true,
})
hl.window_rule({ match = { class = "org\\.freecad\\.FreeCAD", title = "Expression editor" }, stay_focused = true })
hl.window_rule({ match = { class = "org\\.freecad\\.FreeCAD", title = "Expression Editor" }, stay_focused = true })
hl.window_rule({ match = { class = "org\\.freecad\\.FreeCAD" }, force_rgbx = true })
hl.window_rule({ match = { class = "org\\.freecad\\.FreeCAD" }, opaque = true })
hl.window_rule({ match = { class = "org\\.freecad\\.FreeCAD" }, opacity = "1.0 override 1.0 override" })
hl.window_rule({ match = { class = "org\\.freecad\\.FreeCAD" }, no_blur = true })

-- dragon-drop
hl.window_rule({ match = { class = "dragon-drop" }, float = true })
hl.window_rule({ match = { class = "dragon-drop" }, pin = true })
hl.window_rule({ match = { class = "dragon-drop" }, no_initial_focus = true })
hl.window_rule({ match = { class = "dragon-drop" }, move = "(monitor_w-window_w-20) (monitor_h-window_h-20)" })

-- Confine floating windows (allow 70% off-screen)
if hl.plugin.confined_floats ~= nil then
	hl.window_rule({
		match = { class = ".*" },
		["confined-floats:confine"] = "-70%",
	})
end

-- Plugin settings (disabled: kinetic-scroll needs update for Hyprland 0.55)
--[[ hl.config({
    ["plugin:kinetic-scroll"] = {
        enabled               = 1,
        friction              = 0.009,
        decel                 = 0.99,
        min_velocity          = 0.45,
        interval_ms           = 8,
        delta_multiplier      = 1.0,
        velocity_relevance_ms = 70,
        min_sample_ms         = 6,
        max_velocity_samples  = 6,
        disable_in_browser    = 1,
        stop_on_target_change = 1,
        stop_on_click         = 1,
        stop_on_focus         = 1,
        debug                 = 0,
    },
}) --]]

if hl.plugin.scrolloverview then
	hl.plugin.scrolloverview.configure({
		gesture_distance = 300,
		scale = 0.5,
		workspace_gap = 100,
	})
end

-- Keybinds
hl.bind(mainMod .. " + W", hl.dsp.window.close())
hl.bind(mainMod .. " + SHIFT + L", hl.dsp.exec_cmd(env.noctalia .. " ipc call lockScreen lock"))

-- Focus movement
hl.bind(mainMod .. " + left", hl.dsp.focus({ direction = "left" }))
hl.bind(mainMod .. " + right", hl.dsp.focus({ direction = "right" }))
hl.bind(mainMod .. " + up", hl.dsp.layout("focus u"))
hl.bind(mainMod .. " + down", hl.dsp.layout("focus d"))

hl.bind(mainMod .. " + h", hl.dsp.focus({ direction = "l" }))
hl.bind(mainMod .. " + l", hl.dsp.focus({ direction = "r" }))
hl.bind(mainMod .. " + k", hl.dsp.layout("move -col"))
hl.bind(mainMod .. " + j", hl.dsp.layout("move +col"))

-- Scrolling layout
hl.bind(mainMod .. " + period", hl.dsp.layout("move +col"))
hl.bind(mainMod .. " + comma", hl.dsp.layout("move -col"))
hl.bind(mainMod .. " + SHIFT + period", hl.dsp.layout("swapcol r"))
hl.bind(mainMod .. " + SHIFT + comma", hl.dsp.layout("swapcol l"))
hl.bind(mainMod .. " + bracketright", hl.dsp.layout("colresize +conf"))
hl.bind(mainMod .. " + bracketleft", hl.dsp.layout("colresize -conf"))
hl.bind(mainMod .. " + f", hl.dsp.layout("fit visible"))
hl.bind(mainMod .. " + SHIFT + f", hl.dsp.layout("fit all"))
hl.bind(mainMod .. " + p", function()
	local win = hl.get_active_window()
	if not win or win.floating then
		return
	end

	local layout = win.layout
	if not layout or layout.name ~= "scrolling" then
		return
	end
	if not layout.column then
		return
	end

	local count = #layout.column.windows
	if count <= 1 then
		return
	end

	local my_idx = layout.index_in_column -- 0-based
	local above = my_idx
	local below = count - my_idx - 1
	local my_addr = win.address

	if above == 0 then
		hl.dispatch(hl.dsp.layout("promote"))
		hl.dispatch(hl.dsp.layout("swapcol l"))
	elseif below == 0 then
		hl.dispatch(hl.dsp.layout("promote"))
	else
		for i = 1, below do
			hl.dispatch(hl.dsp.layout("expel"))
		end
		if below > 1 then
			hl.dispatch(hl.dsp.layout("focus r"))
			for i = 1, below - 1 do
				hl.dispatch(hl.dsp.layout("consume"))
			end
		end
		hl.dispatch(hl.dsp.exec_raw("focuswindow address:" .. my_addr))
		hl.dispatch(hl.dsp.layout("promote"))
	end

	hl.dispatch(hl.dsp.exec_raw("focuswindow address:" .. my_addr))
end)

-- Layout switching
hl.bind(mainMod .. " + ALT + s", hl.dsp.layout("setlayout, scrolling"))
hl.bind(mainMod .. " + ALT + d", hl.dsp.layout("setlayout, dwindle"))
hl.bind(mainMod .. " + ALT + m", hl.dsp.layout("setlayout, master"))

-- Workspaces
for i = 1, 9 do
	hl.bind(mainMod .. " + " .. i, hl.dsp.exec_raw("focusworkspaceoncurrentmonitor " .. i))
	hl.bind(mainMod .. " + SHIFT + " .. i, hl.dsp.window.move({ workspace = i }))
end

-- Overview
hl.bind(mainMod .. " + TAB", function()
	if hl.plugin.scrolloverview then
		hl.plugin.scrolloverview.overview("toggle")
	end
end)

-- Media keys (locked + repeating)
hl.bind(
	"XF86AudioRaiseVolume",
	hl.dsp.exec_cmd(env.wpctl .. " set-volume @DEFAULT_AUDIO_SINK@ 5%+ -l 1.0"),
	{ locked = true, repeating = true }
)
hl.bind(
	"XF86AudioLowerVolume",
	hl.dsp.exec_cmd(env.wpctl .. " set-volume @DEFAULT_AUDIO_SINK@ 5%-"),
	{ locked = true, repeating = true }
)
hl.bind("XF86MonBrightnessUp", hl.dsp.exec_cmd(env.brightnessctl .. " set +5%"), { locked = true, repeating = true })
hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd(env.brightnessctl .. " set 5%-"), { locked = true, repeating = true })

-- Media keys (locked only)
hl.bind("XF86AudioMute", hl.dsp.exec_cmd(env.wpctl .. " set-mute @DEFAULT_AUDIO_SINK@ toggle"), { locked = true })
hl.bind("XF86AudioNext", hl.dsp.exec_cmd(env.playerctl .. " next"), { locked = true })
hl.bind("XF86AudioPrev", hl.dsp.exec_cmd(env.playerctl .. " previous"), { locked = true })
hl.bind("XF86AudioPlay", hl.dsp.exec_cmd(env.playerctl .. " play-pause"), { locked = true })
hl.bind("XF86AudioPause", hl.dsp.exec_cmd(env.playerctl .. " play-pause"), { locked = true })

-- Mouse binds
hl.bind(mainMod .. " + mouse:272", hl.dsp.window.drag(), { mouse = true })
hl.bind(mainMod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })

-- Source mutable user overrides
pcall(require, "user")

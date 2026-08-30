-- TV config: fullscreen-looking scrolling tape, driven by a remote/touchpad.
-- Deliberately lean -- no event handlers, no polling timers, no custom layout
-- logic. If you need a one-off tweak on the box itself, put it in user.lua.
local env = require("nix-env")
local mainMod = "SUPER"

-- Plugins: kinetic-scroll (touchpad momentum) and scroll-overview (the primary
-- navigation surface). Generated from the Nix plugin modules.
require("plugins")

-- Single HDMI output, no fractional scaling.
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = env.display_scale })

hl.config({
	ecosystem = {
		no_update_news = true,
	},

	-- Zero gaps/borders/rounding everywhere: on a TV, edge decoration is just
	-- wasted pixels behind the overscan.
	general = {
		layout = "scrolling",
		gaps_in = 0,
		gaps_out = 0,
		border_size = 0,
	},

	-- column_width maxes out at exactly 1.0, so every column fills the monitor.
	-- Windows therefore always *look* fullscreen while the tape still scrolls
	-- left/right, and nothing is ever partially off-screen.
	scrolling = {
		direction = "right",
		column_width = 1.0,
		fullscreen_on_one_column = true,
		focus_fit_method = 0, -- 0 = center, 1 = fit
		wrap_focus = true,
	},

	decoration = {
		rounding = 0,
		blur = {
			enabled = false,
		},
	},

	misc = {
		disable_hyprland_logo = true,
		force_default_wallpaper = 0,
		focus_on_activate = true,
		-- Any input wakes the panel, so SUPER+SHIFT+D is a fallback rather than
		-- the only way out of a DPMS-off state.
		mouse_move_enables_dpms = true,
		key_press_enables_dpms = true,
	},

	-- Let fullscreen video bypass compositing entirely. Meaningful power and
	-- quality win on this iGPU.
	render = {
		direct_scanout = 2, -- 0 = off, 1 = on, 2 = auto
	},

	cursor = {
		warp_on_change_workspace = true,
		inactive_timeout = 3,
		hide_on_key_press = true,
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

	gestures = {
		scrolling = {
			move_snap_to_grid = true,
			move_snap_cursor = true,
		},
	},

	animations = {
		enabled = true,
	},
})

-- Curves & animations
hl.curve("snap", { type = "bezier", points = { { 0.2, 1 }, { 0.3, 1 } } })
hl.curve("smooth", { type = "bezier", points = { { 0.25, 0.8 }, { 0.25, 1 } } })

hl.animation({ leaf = "global", enabled = true, speed = 2, bezier = "snap" })
hl.animation({ leaf = "windowsMove", enabled = true, speed = 6, bezier = "snap" })
hl.animation({ leaf = "workspaces", enabled = true, speed = 2, bezier = "snap", style = "slidevert" })

-- Gestures
hl.gesture({ fingers = 3, direction = "horizontal", action = "scroll_move", scale = 1.0 })
hl.gesture({ fingers = 3, direction = "vertical", action = "workspace" })

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

-- App pinning. Only apps actually installed on this host; add more as needed.
-- Spotify is `silent` because tv-away starts it as a session unit at login and
-- again on resume -- without it, the box would yank you to workspace 2 whenever
-- Spotify comes back.
-- window_rule uses RE2 FullMatch (whole-string, case-sensitive), and Spotify
-- runs under XWayland with WM_CLASS "Spotify" (capital S) rather than a native
-- app_id -- unlike everything else here, so it needs the explicit case-fold.
hl.window_rule({ match = { class = "firefox" }, workspace = "1" })
hl.window_rule({ match = { class = "(?i)spotify" }, workspace = "2 silent" })

-- sway-audio-idle-inhibit already covers audible playback; this covers a paused
-- or silent fullscreen video so the panel doesn't blank mid-movie.
hl.window_rule({ match = { class = "mpv|firefox" }, idle_inhibit = "fullscreen" })

-- Keybinds
hl.bind(mainMod .. " + w", hl.dsp.window.close())
hl.bind(mainMod .. " + f", hl.dsp.window.fullscreen({ mode = "fullscreen", action = "toggle" }))
hl.bind(mainMod .. " + SHIFT + L", hl.dsp.exec_cmd(env.noctalia .. " ipc call lockScreen lock"))

-- Force displays back on. Recovery for a DPMS-off state where the screens are
-- black but the session is alive. Locked so it fires even while displays are
-- off / session idle. Deferred via a oneshot timer: binding DPMS directly can
-- cause undefined behavior, so dispatch it just after the handler returns.
hl.bind(mainMod .. " + SHIFT + D", function()
	hl.timer(function()
		hl.dispatch(hl.dsp.dpms({ action = "enable" }))
	end, { timeout = 100, type = "oneshot" })
end, { locked = true })

-- Navigation: left/right moves along the tape, up/down changes workspace. This
-- matches scroll-overview's vertical layout, so the mental model is identical
-- whether or not the overview is open.
hl.bind(mainMod .. " + left", hl.dsp.focus({ direction = "l" }))
hl.bind(mainMod .. " + right", hl.dsp.focus({ direction = "r" }))
hl.bind(mainMod .. " + up", hl.dsp.focus({ workspace = "e-1" }))
hl.bind(mainMod .. " + down", hl.dsp.focus({ workspace = "e+1" }))

hl.bind(mainMod .. " + h", hl.dsp.focus({ direction = "l" }))
hl.bind(mainMod .. " + l", hl.dsp.focus({ direction = "r" }))
hl.bind(mainMod .. " + k", hl.dsp.focus({ workspace = "e-1" }))
hl.bind(mainMod .. " + j", hl.dsp.focus({ workspace = "e+1" }))

-- Remote mode: bare F1-F4 jump straight to the pinned workspaces, and Menu
-- toggles the overview. Inside the overview the plugin consumes bare arrows and
-- Return itself (and only while it's open), so no submap is needed here.
for i = 1, 4 do
	hl.bind("F" .. i, hl.dsp.focus({ workspace = i }))
end

hl.bind("Menu", function()
	hl.plugin.scrolloverview.overview("toggle all")
end)

-- Couch file browser: a layer-shell overlay (see pkgs/tv-files), toggled via
-- Quickshell's own IPC rather than hl.exec_cmd every press -- the shell stays
-- resident so this is instant, no cold start.
hl.bind("F5", hl.dsp.exec_cmd(env.qs .. " -c tv-files ipc call browser toggle"))
hl.bind(mainMod .. " + F5", hl.dsp.exec_cmd(env.qs .. " -c tv-files ipc call browser toggle"))

-- Workspaces
for i = 1, 9 do
	hl.bind(mainMod .. " + " .. i, hl.dsp.focus({ workspace = i }))
	hl.bind(mainMod .. " + SHIFT + " .. i, hl.dsp.window.move({ workspace = i }))
end

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

-- kanata per-window layer switching, generated by modules/keylayers when
-- keyLayers.enable = true; absent (and silently skipped) otherwise.
pcall(require, "kanata-app-layers")

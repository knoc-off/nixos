local env = require("nix-env")

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
		column_width = 1.0,
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

-- Auto-stack: if the previously focused window is alone in its column,
-- stack the new window on top of it instead of creating a new column.
hl.on("window.open", function(window)
	if window.floating then
		return
	end

	local prev = hl.get_last_window()
	if not prev or prev.floating then
		return
	end

	local layout = prev.layout
	if not layout or layout.name ~= "scrolling" then
		return
	end
	if not layout.column then
		return
	end

	if #layout.column.windows == 1 then
		hl.dispatch(hl.dsp.layout("consume_or_expel prev"))
	end
end)

-- Keybind modifier
local mainMod = "SUPER"

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

-- Quickshell overview
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
hl.bind(mainMod .. " + mouse:272", hl.dsp.window.drag(),   { mouse = true })
hl.bind(mainMod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })

-- Source mutable user overrides
pcall(require, "user")

{
  programs.btop = {
    enable = true;

    settings = {
      color_theme = "Default";
      theme_background = false;
      #* sets if 24-bit truecolor should be used, will convert 24-bit colors to 256 color (6x6x6 color cube) if false.
      truecolor = true;

      #* set to true to force tty mode regardless if a real tty has been detected or not.
      #* will force 16-color mode and tty theme, set all graph symbols to "tty" and swap out other non tty friendly symbols.
      force_tty = false;

      #* define presets for the layout of the boxes. preset 0 is always all boxes shown with default settings. max 9 presets.
      #* format: "box_name:p:g,box_name:p:g" p=(0 or 1) for alternate positions, g=graph symbol to use for box.
      #* use whitespace " " as separator between different presets.
      #* example: "cpu:0:default,mem:0:tty,proc:1:default cpu:0:braille,proc:0:tty"
      presets = "cpu:1:default,proc:0:default cpu:0:default,mem:0:default,net:0:default cpu:0:block,net:0:tty";

      #* set to true to enable "h,j,k,l,g,g" keys for directional control in lists.
      #* conflicting keys for h:"help" and k:"kill" is accessible while holding shift.
      vim_keys = false;

      #* rounded corners on boxes, is ignored if tty mode is on.
      rounded_corners = true;

      #* default symbols to use for graph creation, "braille", "block" or "tty".
      #* "braille" offers the highest resolution but might not be included in all fonts.
      #* "block" has half the resolution of braille but uses more common characters.
      #* "tty" uses only 3 different symbols but will work with most fonts and should work in a real tty.
      #* note that "tty" only has half the horizontal resolution of the other two, so will show a shorter historical view.
      graph_symbol = "braille";

      # graph symbol to use for graphs in cpu box, "default", "braille", "block" or "tty".
      graph_symbol_cpu = "default";

      # graph symbol to use for graphs in cpu box, "default", "braille", "block" or "tty".
      graph_symbol_mem = "default";

      # graph symbol to use for graphs in cpu box, "default", "braille", "block" or "tty".
      graph_symbol_net = "default";

      # graph symbol to use for graphs in cpu box, "default", "braille", "block" or "tty".
      graph_symbol_proc = "default";

      #* manually set which boxes to show. available values are "cpu mem net proc", separate values with whitespace.
      shown_boxes = "cpu mem net proc";

      #* update time in milliseconds, recommended 2000 ms or above for better sample times for graphs.
      update_ms = 500;

      #* processes sorting, "pid" "program" "arguments" "threads" "user" "memory" "cpu lazy" "cpu direct",
      #* "cpu lazy" sorts top process over time (easier to follow), "cpu direct" updates top process directly.
      proc_sorting = "cpu lazy";

      #* reverse sorting order, true or false.
      proc_reversed = false;

      #* show processes as a tree.
      proc_tree = false;

      #* use the cpu graph colors in the process list.
      proc_colors = true;

      #* use a darkening gradient in the process list.
      proc_gradient = true;

      #* if process cpu usage should be of the core it's running on or usage of the total available cpu power.
      proc_per_core = false;

      #* show process memory as bytes instead of percent.
      proc_mem_bytes = true;

      #* show cpu graph for each process.
      proc_cpu_graphs = true;

      #* use /proc/[pid]/smaps for memory information in the process info box (very slow but more accurate)
      proc_info_smaps = false;

      #* show proc box on left side of screen instead of right.
      proc_left = false;

      #* (linux) filter processes tied to the linux kernel(similar behavior to htop).
      proc_filter_kernel = false;

      #* sets the cpu stat shown in upper half of the cpu graph, "total" is always available.
      #* select from a list of detected attributes from the options menu.
      cpu_graph_upper = "total";

      #* sets the cpu stat shown in lower half of the cpu graph, "total" is always available.
      #* select from a list of detected attributes from the options menu.
      cpu_graph_lower = "total";

      #* toggles if the lower cpu graph should be inverted.
      cpu_invert_lower = true;

      #* set to true to completely disable the lower cpu graph.
      cpu_single_graph = false;

      #* show cpu box at bottom of screen instead of top.
      cpu_bottom = false;

      #* shows the system uptime in the cpu box.
      show_uptime = true;

      #* show cpu temperature.
      check_temp = true;

      #* which sensor to use for cpu temperature, use options menu to select from list of available sensors.
      cpu_sensor = "auto";

      #* show temperatures for cpu cores also if check_temp is true and sensors has been found.
      show_coretemp = true;

      #* set a custom mapping between core and coretemp, can be needed on certain cpus to get correct temperature for correct core.
      #* use lm-sensors or similar to see which cores are reporting temperatures on your machine.
      #* format "x:y" x=core with wrong temp, y=core with correct temp, use space as separator between multiple entries.
      #* example: "4:0 5:1 6:3"
      cpu_core_map = "";

      #* which temperature scale to use, available values: "celsius", "fahrenheit", "kelvin" and "rankine".
      temp_scale = "celsius";

      #* use base 10 for bits/bytes sizes, kb = 1000 instead of kib = 1024.
      base_10_sizes = false;

      #* show cpu frequency.
      show_cpu_freq = true;

      #* draw a clock at top of screen, formatting according to strftime, empty string to disable.
      #* special formatting: /host = hostname | /user = username | /uptime = system uptime
      clock_format = "%x";

      #* update main ui in background when menus are showing, set this to false if the menus is flickering too much for comfort.
      background_update = true;

      #* custom cpu model name, empty string to disable.
      custom_cpu_name = "";

      #* optional filter for shown disks, should be full path of a mountpoint, separate multiple values with whitespace " ".
      #* begin line with "exclude=" to change to exclude filter, otherwise defaults to "most include" filter. example: disks_filter="exclude=/boot /home/user".
      disks_filter = "";

      #* show graphs instead of meters for memory values.
      mem_graphs = true;

      #* show mem box below net box instead of above.
      mem_below_net = false;

      #* count zfs arc in cached and available memory.
      zfs_arc_cached = true;

      #* if swap memory should be shown in memory box.
      show_swap = true;

      #* show swap as a disk, ignores show_swap value above, inserts itself after first disk.
      swap_disk = true;

      #* if mem box should be split to also show disks info.
      show_disks = true;

      #* filter out non physical disks. set this to false to include network disks, ram disks and similar.
      only_physical = true;

      #* read disks list from /etc/fstab. this also disables only_physical.
      use_fstab = true;

      #* setting this to true will hide all datasets, and only show zfs pools. (io stats will be calculated per-pool)
      zfs_hide_datasets = false;

      #* set to true to show available disk space for privileged users.
      disk_free_priv = false;

      #* toggles if io activity % (disk busy time) should be shown in regular disk usage view.
      show_io_stat = true;

      #* toggles io mode for disks, showing big graphs for disk read/write speeds.
      io_mode = false;

      #* set to true to show combined read/write io graphs in io mode.
      io_graph_combined = false;

      #* set the top speed for the io graphs in mib/s (100 by default), use format "mountpoint:speed" separate disks with whitespace " ".
      #* example: "/mnt/media:100 /:20 /boot:1".
      io_graph_speeds = "";

      #* set fixed values for network graphs in mebibits. is only used if net_auto is also set to false.
      net_download = 100;

      net_upload = 100;

      #* use network graphs auto rescaling mode, ignores any values set above and rescales down to 10 kibibytes at the lowest.
      net_auto = true;

      #* sync the auto scaling for download and upload to whichever currently has the highest scale.
      net_sync = true;

      #* starts with the network interface specified here.
      net_iface = "";

      #* show battery stats in top right if battery is present.
      show_battery = true;

      #* which battery to use if multiple are present. "auto" for auto detection.
      selected_battery = "auto";
    };
  };
}

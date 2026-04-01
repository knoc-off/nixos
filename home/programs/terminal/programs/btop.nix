{ self, ... }:
let
  inherit (self.lib) theme;
in {
  programs.btop = {
    enable = true;

    settings = {
      color_theme = "custom";
      theme_background = false;
      truecolor = true;

      force_tty = false;

      presets = "cpu:1:default,proc:0:default cpu:0:default,mem:0:default,net:0:default cpu:0:block,net:0:tty";

      vim_keys = false;

      rounded_corners = true;

      graph_symbol = "braille";

      graph_symbol_cpu = "default";

      graph_symbol_mem = "default";

      graph_symbol_net = "default";

      graph_symbol_proc = "default";

      shown_boxes = "cpu mem net proc";

      update_ms = 500;

      proc_sorting = "cpu lazy";

      proc_reversed = false;

      proc_tree = false;

      proc_colors = true;

      proc_gradient = true;

      proc_per_core = false;

      proc_mem_bytes = true;

      proc_cpu_graphs = true;

      proc_info_smaps = false;

      proc_left = false;

      proc_filter_kernel = false;

      cpu_graph_upper = "total";

      cpu_graph_lower = "total";

      cpu_invert_lower = true;

      cpu_single_graph = false;

      cpu_bottom = false;

      show_uptime = true;

      check_temp = true;

      cpu_sensor = "auto";

      show_coretemp = true;

      cpu_core_map = "";

      temp_scale = "celsius";

      base_10_sizes = false;

      show_cpu_freq = true;

      clock_format = "%x";

      background_update = true;

      custom_cpu_name = "";

      disks_filter = "";

      mem_graphs = true;

      mem_below_net = false;

      zfs_arc_cached = true;

      show_swap = true;

      swap_disk = true;

      show_disks = true;

      only_physical = true;

      use_fstab = true;

      zfs_hide_datasets = false;

      disk_free_priv = false;

      show_io_stat = true;

      io_mode = false;

      io_graph_combined = false;

      io_graph_speeds = "";

      net_download = 100;

      net_upload = 100;

      net_auto = true;

      net_sync = true;

      net_iface = "";

      show_battery = true;

      selected_battery = "auto";
    };
  };

  xdg.configFile."btop/themes/custom.theme".text = with theme.dark; ''
    theme[main_bg]="#${base00}"
    theme[main_fg]="#${base05}"
    theme[title]="#${base06}"
    theme[hi_fg]="#${base0D}"
    theme[selected_bg]="#${base02}"
    theme[selected_fg]="#${base06}"
    theme[inactive_fg]="#${base03}"
    theme[graph_text]="#${base04}"
    theme[meter_bg]="#${base01}"
    theme[proc_misc]="#${base0D}"
    theme[cpu_box]="#${base0D}"
    theme[mem_box]="#${base0B}"
    theme[net_box]="#${base0C}"
    theme[proc_box]="#${base0E}"
    theme[div_line]="#${base01}"
    theme[temp_start]="#${base0B}"
    theme[temp_mid]="#${base0A}"
    theme[temp_end]="#${base08}"
    theme[cpu_start]="#${base0D}"
    theme[cpu_mid]="#${base0E}"
    theme[cpu_end]="#${base08}"
    theme[free_start]="#${base0B}"
    theme[free_mid]="#${base0B}"
    theme[free_end]="#${base0B}"
    theme[cached_start]="#${base0D}"
    theme[cached_mid]="#${base0D}"
    theme[cached_end]="#${base0D}"
    theme[available_start]="#${base0C}"
    theme[available_mid]="#${base0C}"
    theme[available_end]="#${base0C}"
    theme[used_start]="#${base0A}"
    theme[used_mid]="#${base09}"
    theme[used_end]="#${base08}"
    theme[download_start]="#${base0D}"
    theme[download_mid]="#${base0C}"
    theme[download_end]="#${base0C}"
    theme[upload_start]="#${base0E}"
    theme[upload_mid]="#${base09}"
    theme[upload_end]="#${base08}"
    theme[process_start]="#${base0D}"
    theme[process_mid]="#${base0E}"
    theme[process_end]="#${base0C}"
  '';
}

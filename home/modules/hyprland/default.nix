# The goal of this module is to setup a decent base.
{ config, lib, theme, pkgs, inputs, ... }:

let
  cfg = config.wayland.windowManager.hyprlandCustom;
in

{
  imports = [
    ./dunst.nix
    ./pyprland.nix
    ./swayidle.nix
    ./settings/binds.nix
  ];

  options.wayland.windowManager.hyprlandCustom = {
    enable = lib.mkEnableOption "Hyprland window manager";
    package = lib.mkOption {
      type = lib.types.package;
      default = inputs.hyprland.packages.${pkgs.system}.hyprland;
      description = "Hyprland package to use.";
    };
    modkey = lib.mkOption {
      type = lib.types.str;
      default = "SUPER";
      description = "Hyprland modifier key.";
    };
    plugins = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = with inputs.hyprland-plugins.packages.${pkgs.system}; [];
      description = "Hyprland plugins to use.";
    };
    settings = lib.mkOption {
      type = lib.types.attrs;
      default = {};
      description = "Hyprland configuration settings.";
    };
  };

  config = lib.mkIf cfg.enable {


    services.cliphist = {
      enable = true;
      allowImages = true;
      extraOptions = [ "--history-size=1000" ];
      systemdTarget = "hyprland-session.target";
    };

    programs.rofi = {
      enable = true;
      package = pkgs.rofi;
      font = "Droid Sans 9";
      location = "center";
      xoffset = 0;
      yoffset = 0;
      extraConfig = {
        modi = "drun,run,clipboard:cliphist";
        show-icons = true;
        display-drun = "Applications";
        display-run = "Run";
        display-clipboard = "Clipboard";
        drun-display-format = "{icon} {name}";
        clipboard-histroy = 20;
      };
      #theme = "~/path/to/your/rofi/theme.rasi";
    };


    # lockscreen
    programs.swaylock = {
      package = pkgs.swaylock-effects;
    };

    # wallpaper manager
    home.packages = [
      pkgs.hyprpaper
    ];

    # Window manager
    wayland.windowManager.hyprland = {
      enable = true;
      package = cfg.package;
      systemd.enable = true;
      xwayland.enable = true;
      plugins = cfg.plugins;

      settings = lib.mkMerge [
        cfg.settings
        (import ./settings/general.nix { inherit config inputs theme lib pkgs; })
      ];
    };

    # plugins
    pyprland = {
      enable = true;
      extraPlugins = [
        "expose"
      ];

      settings = {
        scratchpads = {
          file = {
            animation = "fromBottom";
            command = "nemo";
            class = "nemo";
            size = "75% 60%";
            #unfocus = "hide";
          };
          foxy = {
            animation = "fromRight";
            command = "firefox --no-remote -P minimal --name firefox-minimal https://duck.com";
            class = "firefox-minimal";
            size = "55% 90%";
          };
          volume = {
            animation = "fromRight";
            command = "${pkgs.pavucontrol}/bin/pavucontrol";
            class = "pavucontrol";
            lazy = true;
            size = "40% 90%";
            #unfocus = "hide";
          };
          stb-logs = {
            animation = "fromTop";
            command = "kitty --class kitty-stb-logs stbLog";
            class = "kitty-stb-logs";
            lazy = true;
            size = "75% 40%";
          };
          term = {
            animation = "fromTop";
            command = "kitty --class kitty-dropterm --config <(sed '/map ctrl+t new_os_window_with_cwd/d' /home/knoff/.config/kitty/kitty.conf)";
            class = "kitty-dropterm";
            #unfocus = "hide";
            #match_by =  "pid";
            #hysteresis = 0;
            size = "75% 60%";
          };
        };
      };
    };
  };
}

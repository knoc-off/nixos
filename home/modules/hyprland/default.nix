# The goal of this module is to setup a decent base.
{
  config,
  lib,
  theme,
  pkgs,
  inputs,
  colorLib,
  user,
  ...
}: let
  cfg = config.wayland.windowManager.hyprlandCustom;
in {
  imports = [
    # AGS is my notifier
    ./dunst.nix
    #./pyprland.nix
    ./swayidle.nix
    ./settings/binds.nix
    inputs.hyprland.homeManagerModules.default
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
      default = with inputs.hyprland-plugins.packages.${pkgs.system};
        [
          #hyprexpo


        ];
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
      extraOptions = ["--history-size=1000"];
      systemdTarget = "hyprland-session.target";
    };

    programs.rofi = {
      enable = true;
      package = pkgs.rofi-wayland;
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
        (import ./settings/general.nix {inherit config inputs user theme lib pkgs colorLib;})
      ];
    };

  };
}

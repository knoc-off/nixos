{
  inputs,
  pkgs,
  theme,
  config,
  lib,
  ...
}: let
  # theres a few unchecked dependencies here.
  # like notify-send, etc. could link it like i do with fuzzle
  hyprland = inputs.hyprland.packages.${pkgs.system}.hyprland;
  plugins = inputs.hyprland-plugins.packages.${pkgs.system};

  notify-send = "${pkgs.libnotify}/bin/notify-send";

  # hyprpaper config
  # need to put the wallpaper into the nix-store.
  wallpaper = let
    wallpaper-img = pkgs.fetchurl {
      url = "https://images.squarespace-cdn.com/content/v1/6554594506867677bdd68b03/a30ca789-db30-4413-8dc5-40726c893d7a/SCAV+new+intro+bg+02+copy.jpg";
      sha256 = "sha256-oGjPyBq56rweu7/Lo9SJudF/vg7uL1X/qpus9fFkEmw="; # Replace with the actual SHA-256 hash
    };
  in
    pkgs.writeText "wallpaper"
    ''
      preload = ${wallpaper-img}
      wallpaper = eDP-1, ${wallpaper-img}
      splash = false
    '';
in {
  imports = [
    ./dunst.nix
    ./pyprland.nix

    ./swayidle.nix

    ./settings/binds.nix
  ];

  programs.swaylock = {
    package = pkgs.swaylock-effects;
  };

  home.packages = [
    pkgs.hyprpaper
  ];
  xdg.desktopEntries."org.gnome.Settings" = {
    name = "Settings";
    comment = "Gnome Control Center";
    icon = "org.gnome.Settings";
    exec = "env XDG_CURRENT_DESKTOP=gnome ${pkgs.gnome.gnome-control-center}/bin/gnome-control-center";
    categories = ["X-Preferences"];
    terminal = false;
  };

  # ~~~~~~~~~

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

  # ~~~~~~~~~

  wayland.windowManager.hyprland = {
    enable = true;
    package = hyprland;
    systemd.enable = true;
    xwayland.enable = true;
    plugins = with plugins; [];

    settings = {
    };
  };
}

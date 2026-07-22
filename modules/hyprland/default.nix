{
  inputs,
  self,
}: let
  hyprnixPkgs = system: inputs.hyprnix.packages.${system};
  hyprqt6engine = system: inputs.hyprqt6engine.packages.${system}.default;
in {
  nixos = {
    config,
    lib,
    pkgs,
    ...
  }: let
    system = pkgs.stdenv.hostPlatform.system;
    hyprnix = hyprnixPkgs system;
  in {
    programs.hyprland = {
      enable = true;
      package = hyprnix.hyprland;
      portalPackage = hyprnix.xdg-desktop-portal-hyprland;
      withUWSM = true;
    };

    security.polkit.enable = true;

    environment.systemPackages = with pkgs; [
      wl-clipboard
      xdg-utils
    ];

    xdg.portal = {
      enable = true;
      extraPortals = [pkgs.xdg-desktop-portal-gtk];
      config.common.default = ["hyprland" "gtk"];
    };

    environment.sessionVariables.NIXOS_OZONE_WL = "1";

    # Fix hyprland-share-picker crash: the picker (Qt6 from hyprnix) segfaults when
    # it loads the session's Kvantum style plugin due to Qt version mismatch
    # (nixpkgs Qt 6.10.1 vs hyprnix Qt 6.10.2). Use hyprqt6engine built against
    # hyprnix's Qt so the platform theme plugin is ABI-compatible with the picker.
    systemd.user.services.xdg-desktop-portal-hyprland.serviceConfig.Environment = let
      engine = hyprqt6engine system;
    in [
      "QT_QPA_PLATFORMTHEME=hyprqt6engine"
      "QT_STYLE_OVERRIDE="
      "QT_PLUGIN_PATH=${engine}/lib/qt-6/plugins"
    ];
  };

  home = {
    inputs,
    config,
    lib,
    pkgs,
    self,
    ...
  }: let
    inherit (self.lib) color-lib theme;
    system = pkgs.stdenv.hostPlatform.system;
    hyprnix = hyprnixPkgs system;
    noctaliaCmd = lib.getExe config.programs.noctalia-shell.package;
    noctalia = cmd: "${noctaliaCmd} ipc call ${cmd}";

    displayScale = 1.171339564;

    kinetic-scroll = import ./plugins/kinetic-scroll.nix {inherit inputs pkgs lib;};
    # confined-floats = import ./plugins/confined-floats.nix {inherit inputs pkgs lib;};
    scroll-overview = import ./plugins/scroll-overview.nix {inherit inputs pkgs lib;};

    nixEnvLua = pkgs.writeText "nix-env.lua" ''
      local M = {}
      M.noctalia = "${noctaliaCmd}"
      M.wpctl = "${pkgs.wireplumber}/bin/wpctl"
      M.brightnessctl = "${lib.getExe pkgs.brightnessctl}"
      M.playerctl = "${lib.getExe pkgs.playerctl}"
      M.kinetic_scroll_so = "${kinetic-scroll}/lib/libhypr-kinetic-scroll.so"
      M.scroll_overview_so = "${scroll-overview}/lib/libscrolloverview.so"
      M.qs_overview_cmd = "echo 'no'"
      M.display_scale = ${toString displayScale}
      return M
    '';
  in {
    # XWayland renders at 96 DPI without this -- compositor upscales (blurry)
    xresources.properties."Xft.dpi" = builtins.floor (96 * displayScale);

    # hyprqt6engine: match Stylix fonts so screen-share picker looks consistent
    xdg.configFile."hypr/hyprqt6engine.conf".text = let
      fonts = config.stylix.fonts;
    in ''
      theme {
          style = Fusion
          icon_theme = ${config.gtk.iconTheme.name}
          font = ${fonts.sansSerif.name}
          font_size = ${toString fonts.sizes.applications}
          font_fixed = ${fonts.monospace.name}
          font_fixed_size = ${toString fonts.sizes.terminal}
      }
    '';

    services.hypridle = {
      enable = true;
      settings = {
        general = {
          lock_cmd = "${noctaliaCmd} ipc call lockScreen lock"; # triggered by loginctl lock-session
          before_sleep_cmd = "loginctl lock-session"; # always lock before sleep
          after_sleep_cmd = "hyprctl dispatch 'hl.dsp.dpms({ action = \"enable\" })'"; # restore monitors after wake
        };

        listener = [
          {
            timeout = 300; # 5 minutes
            on-timeout = "loginctl lock-session";
          }
          {
            timeout = 600; # 10 minutes
            on-timeout = "hyprctl dispatch 'hl.dsp.dpms({ action = \"disable\" })'";
            on-resume = "hyprctl dispatch 'hl.dsp.dpms({ action = \"enable\" })'";
          }
          {
            timeout = 1800; # 30 minutes
            on-timeout = "${pkgs.systemd}/bin/systemctl suspend";
          }
        ];
      };
    };

    wayland.windowManager.hyprland = {
      enable = true;
      package = hyprnix.hyprland;
      systemd.enable = false; # UWSM handles session/systemd integration

      configType = "lua";
    };

    xdg.configFile."hypr/hyprland.lua".source = ./hyprland.lua;
    xdg.configFile."hypr/nix-env.lua".source = nixEnvLua;

    home.activation.seedHyprUserConfig = lib.hm.dag.entryAfter ["writeBoundary"] ''
      target="$HOME/.config/hypr/user.lua"
      if [ ! -f "$target" ]; then
        install -Dm644 ${./user-default.lua} "$target"
      fi
    '';

    systemd.user.services.workspace-wallpaper-daemon = let
      inherit (color-lib) setOkhslLightness setOkhslSaturation adjustOkhslHue;

      wsColors = theme.dark.workspaceColors;
      numWsColors = builtins.length wsColors;

      mkWsPalette = wsHex: let
        base = "#${wsHex}";
        # Primary accent: bright, saturated version of the workspace hue
        primary = "#${setOkhslLightness 0.65 (setOkhslSaturation 0.85 base)}";
        secondary = "#${setOkhslLightness 0.60 (setOkhslSaturation 0.70 (adjustOkhslHue 0.08 base))}";
        tertiary = "#${setOkhslLightness 0.60 (setOkhslSaturation 0.70 (adjustOkhslHue (-0.12) base))}";
        error = "#${theme.dark.base08}";
        surface = "#${theme.dark.base00}";
        surfaceVar = "#${theme.dark.base01}";
        onSurface = "#${theme.dark.base05}";
        onSurfVar = "#${theme.dark.base04}";
        outline = "#${theme.dark.base03}";
        hover = "#${theme.dark.base02}";
        onBg = "#${theme.dark.base00}";
        onHover = "#${theme.dark.base06}";
      in
        builtins.toJSON {
          mPrimary = primary;
          mOnPrimary = onBg;
          mSecondary = secondary;
          mOnSecondary = onBg;
          mTertiary = tertiary;
          mOnTertiary = onBg;
          mError = error;
          mOnError = onBg;
          mSurface = surface;
          mOnSurface = onSurface;
          mSurfaceVariant = surfaceVar;
          mOnSurfaceVariant = onSurfVar;
          mOutline = outline;
          mShadow = "#000000";
          mHover = hover;
          mOnHover = onHover;
        };

      # Generate solid-color PNG files and colors.json palettes at build time
      workspaceWallpapers =
        pkgs.runCommand "workspace-wallpapers" {
          nativeBuildInputs = [pkgs.imagemagick];
        } ''
          mkdir -p $out
          ${lib.concatImapStringsSep "\n" (i: color: ''
              magick -size 256x256 xc:'#${color}' $out/ws-${toString i}.png
              echo '${mkWsPalette color}' > $out/ws-${toString i}.json
            '')
            wsColors}
        '';

      # Daemon script: listens for Hyprland workspace changes, sets wallpaper + colors per-monitor
      workspaceWallpaperDaemon = pkgs.writeShellScript "workspace-wallpaper-daemon" ''
        set -euo pipefail

        NOCTALIA="${noctaliaCmd}"
        WALLPAPER_DIR="${workspaceWallpapers}"
        COLORS_FILE="$HOME/.config/noctalia/colors.json"
        NUM_COLORS=${toString numWsColors}

        # Map workspace ID to index (1-indexed, wraps with modulo)
        ws_index() {
          local ws_id=$1
          echo $(( ((ws_id - 1) % NUM_COLORS) + 1 ))
        }

        # Set wallpaper for a specific monitor based on its active workspace
        update_monitor() {
          local monitor=$1
          local ws_id=$2
          local idx
          idx=$(ws_index "$ws_id")
          "$NOCTALIA" ipc call wallpaper set "$WALLPAPER_DIR/ws-''${idx}.png" "$monitor" &
        }

        # Update the color palette based on the focused monitor's workspace
        update_colors() {
          local ws_id=$1
          local idx
          idx=$(ws_index "$ws_id")
          cat "$WALLPAPER_DIR/ws-''${idx}.json" > "$COLORS_FILE"
        }

        # Sync all monitors on startup
        sync_all() {
          local focused_ws=""
          ${pkgs.hyprland}/bin/hyprctl monitors -j | ${pkgs.jq}/bin/jq -r '.[] | "\(.name) \(.activeWorkspace.id) \(.focused)"' | while read -r mon ws focused; do
            update_monitor "$mon" "$ws"
            if [ "$focused" = "true" ]; then
              update_colors "$ws"
            fi
          done
        }

        # Wait for noctalia to be ready
        for i in $(seq 1 30); do
          if "$NOCTALIA" ipc call state all >/dev/null 2>&1; then
            break
          fi
          sleep 1
        done

        sync_all

        # Listen for Hyprland IPC events
        ${pkgs.socat}/bin/socat -U - "UNIX-CONNECT:$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock" | while IFS= read -r line; do
          case "$line" in
            workspacev2\>\>*)
              # workspacev2>>ID,NAME - active workspace changed, update the focused monitor
              ws_id="''${line#workspacev2>>}"
              ws_id="''${ws_id%%,*}"
              focused_mon=$(${pkgs.hyprland}/bin/hyprctl monitors -j | ${pkgs.jq}/bin/jq -r '.[] | select(.focused) | .name')
              if [ -n "$focused_mon" ] && [ "$ws_id" -gt 0 ] 2>/dev/null; then
                update_monitor "$focused_mon" "$ws_id"
                update_colors "$ws_id"
              fi
              ;;
            focusedmon\>\>*)
              # focusedmon>>MONNAME,WSID - focus moved to a different monitor
              payload="''${line#focusedmon>>}"
              mon="''${payload%%,*}"
              ws_id="''${payload#*,}"
              if [ -n "$mon" ] && [ "$ws_id" -gt 0 ] 2>/dev/null; then
                update_monitor "$mon" "$ws_id"
                update_colors "$ws_id"
              fi
              ;;
            moveworkspacev2\>\>*)
              # moveworkspacev2>>WSID,WSNAME,MONNAME - workspace moved to different monitor
              payload="''${line#moveworkspacev2>>}"
              ws_id="''${payload%%,*}"
              rest="''${payload#*,}"
              mon="''${rest#*,}"
              if [ -n "$mon" ] && [ "$ws_id" -gt 0 ] 2>/dev/null; then
                update_monitor "$mon" "$ws_id"
              fi
              ;;
            monitoraddedv2\>\>*)
              # New monitor connected - sync all
              sleep 1
              sync_all
              ;;
          esac
        done
      '';
    in {
      Unit = {
        Description = "Hyprland workspace wallpaper and color daemon";
        After = ["noctalia-shell.service" "graphical-session.target"];
        PartOf = ["graphical-session.target"];
        ConditionEnvironment = "HYPRLAND_INSTANCE_SIGNATURE";
      };
      Service = {
        ExecStart = "${workspaceWallpaperDaemon}";
        Restart = "on-failure";
        RestartSec = 2;
      };
      Install.WantedBy = ["graphical-session.target"];
    };
  };
}

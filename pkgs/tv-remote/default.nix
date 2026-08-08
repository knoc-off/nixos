# Actions exposed as KDE Connect run-commands. They arrive via `/bin/sh -c`
# from kdeconnectd, so keeping the logic here rather than in the command string
# avoids nesting lua inside shell inside JSON inside a QSettings ini value.
{
  lib,
  writeShellApplication,
  coreutils,
  findutils,
  hyprland,
  jq,
  systemd,
}:
writeShellApplication {
  name = "tv-remote";

  runtimeInputs = [
    coreutils
    findutils
    hyprland
    jq
    systemd
  ];

  text = ''
    # kdeconnectd's unit pins PATH but inherits the rest of the session
    # environment, which is normally enough. Rediscover the socket anyway so
    # the command still works when run from ssh or a bare shell.
    if [ -z "''${HYPRLAND_INSTANCE_SIGNATURE:-}" ]; then
      runtime="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
      if [ -d "$runtime/hypr" ]; then
        readarray -t instances < <(
          find "$runtime/hypr" -mindepth 1 -maxdepth 1 -type d -printf '%T@ %f\n' | sort -rn
        )
        if [ "''${#instances[@]}" -gt 0 ]; then
          HYPRLAND_INSTANCE_SIGNATURE="''${instances[0]#* }"
          export HYPRLAND_INSTANCE_SIGNATURE
        fi
      fi
    fi

    dispatch() {
      hyprctl dispatch "$1" >/dev/null
    }

    # Match case-insensitively: XWayland clients report a capitalised WM_CLASS
    # (Spotify), while native wayland clients report a lowercase app_id.
    running() {
      hyprctl -j clients | jq -e --arg c "$1" \
        '[.[] | select(.class | test($c; "i"))] | length > 0' >/dev/null
    }

    usage() {
      cat <<'EOF'
    usage: tv-remote <command>

      ws N        focus workspace N
      next|prev   focus the next/previous window along the tape
      close       close the focused window
      launcher    toggle the noctalia launcher
      app NAME    focus NAME if running, else start it (firefox, spotify)
      sleep       blank the screen and tear down tv-active.target
    EOF
    }

    case "''${1:-}" in
      ws)
        [ -n "''${2:-}" ] || { echo "tv-remote: ws needs a workspace" >&2; exit 1; }
        dispatch "hl.dsp.focus({ workspace = \"$2\" })"
        ;;
      next) dispatch 'hl.dsp.focus({ direction = "r" })' ;;
      prev) dispatch 'hl.dsp.focus({ direction = "l" })' ;;
      close) dispatch 'hl.dsp.window.close()' ;;
      # From $PATH deliberately: this must hit the noctalia instance actually
      # running in the session, not a separately built one.
      launcher) noctalia-shell ipc call launcher toggle ;;
      app)
        case "''${2:-}" in
          firefox)
            if running firefox; then
              dispatch 'hl.dsp.focus({ window = "class:firefox" })'
            else
              dispatch 'hl.dsp.exec_cmd("firefox")'
            fi
            ;;
          spotify)
            if running spotify; then
              dispatch 'hl.dsp.focus({ window = "class:(?i)spotify" })'
            else
              # Started as a unit so it rejoins tv-active.target and is torn
              # down again on the next idle timeout.
              systemctl --user start spotify.service
            fi
            ;;
          *) echo "tv-remote: unknown app ''${2:-}" >&2; exit 1 ;;
        esac
        ;;
      sleep)
        # tv-away.service is the same path hypridle's timeout uses -- it
        # freezes windowed apps (Spotify) instead of stopping them, which
        # matters: killing a window while the session is idled makes
        # Hyprland emit a bogus resume event that immediately undoes the
        # teardown.
        systemctl --user start tv-away.service
        dispatch 'hl.dsp.dpms({ action = "disable" })'
        ;;
      -h | --help | "") usage ;;
      *) echo "tv-remote: unknown command $1" >&2; usage >&2; exit 1 ;;
    esac
  '';

  meta = {
    description = "Session actions for the TV, driven from a phone over KDE Connect";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
    mainProgram = "tv-remote";
  };
}

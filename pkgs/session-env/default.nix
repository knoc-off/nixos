# An SSH login gets a PAM session with none of the Wayland session state, so
# hyprctl, wpctl and anything else talking to the compositor fails for no
# visible reason. Deliberately does not switch users: that is `su -`'s job.
{
  lib,
  writeShellApplication,
  coreutils,
  findutils,
  systemd,
}:
writeShellApplication {
  name = "session-env";

  runtimeInputs = [
    coreutils
    findutils
    systemd
  ];

  text = ''
    if [ "''${1:-}" = "-h" ] || [ "''${1:-}" = "--help" ]; then
      cat <<'EOF'
    usage: session-env [COMMAND [ARG...]]

    Run COMMAND -- or an interactive shell, if none is given -- with the
    environment of your running graphical session. Run it as the session's own
    user, e.g. after `su - tv`.
    EOF
      exit 0
    fi

    uid=$(id -u)
    runtime=/run/user/$uid

    if [ ! -d "$runtime" ]; then
      echo "session-env: $runtime is missing; $(id -un) has no logind session" >&2
      exit 1
    fi

    export XDG_RUNTIME_DIR="$runtime"
    export DBUS_SESSION_BUS_ADDRESS="unix:path=$runtime/bus"

    # UWSM pushes the session environment into the systemd user manager, so that
    # is the authoritative copy. Values come back shell-quoted, hence the eval.
    while IFS= read -r line; do
      case $line in
        [A-Za-z_]*=*) eval "export $line" ;;
      esac
    done < <(systemctl --user show-environment 2>/dev/null)

    # Fallbacks for a session that never finished exporting its environment.
    if [ -z "''${HYPRLAND_INSTANCE_SIGNATURE:-}" ] && [ -d "$runtime/hypr" ]; then
      readarray -t instances < <(
        find "$runtime/hypr" -mindepth 1 -maxdepth 1 -type d -printf '%T@ %f\n' | sort -rn
      )
      if [ "''${#instances[@]}" -gt 0 ]; then
        export HYPRLAND_INSTANCE_SIGNATURE="''${instances[0]#* }"
      fi
    fi

    if [ -z "''${WAYLAND_DISPLAY:-}" ]; then
      readarray -t sockets < <(
        find "$runtime" -maxdepth 1 -type s -name 'wayland-*' -printf '%f\n' | sort
      )
      if [ "''${#sockets[@]}" -gt 0 ]; then
        export WAYLAND_DISPLAY="''${sockets[0]}"
      fi
    fi

    if [ -z "''${WAYLAND_DISPLAY:-}" ]; then
      echo "session-env: no wayland socket in $runtime; is the session running?" >&2
      exit 1
    fi

    if [ "$#" -eq 0 ]; then
      exec "''${SHELL:-/bin/sh}"
    fi

    exec "$@"
  '';

  meta = {
    description = "Run a command with the environment of your running Wayland session";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
    mainProgram = "session-env";
  };
}

# Scheduled Claude keepalive ping. An RTC-wake timer pulls the laptop out of
# suspend at fixed times so the usage window starts when we want it to, runs a
# throwaway prompt, and then leaves the machine alone -- the normal idle path
# (hypridle) is what puts it back to sleep.
#
# Split into two units on purpose:
#
#   claude-ping.service      root -- network wait + logind inhibitor
#     `-- claude-ping-run.service   User= -- the claude invocation itself
#
# polkit resolves a subject's session from the *process cgroup*
# (sd_pid_get_session -> sd_pid_get_owner_uid -> sd_uid_get_display). A system
# unit lives in system.slice, so that chain dead-ends even when User= names the
# logged-in desktop user, and inhibit-block-sleep / inhibit-handle-lid-switch
# fall through to allow_any (auth_admin_keep / no). User units such as hypridle
# inherit the active session's authority via the user slice and can suspend
# freely -- but a user timer cannot arm an RTC wake alarm ("requires privileges
# and is thus generally only available in the system service manager",
# systemd.timer(5)), so the wake has to start from a system timer. Root sidesteps
# polkit entirely, hence the wrapper.
{ ... }:
{
  nixos =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.services.claude-ping;
    in
    {
      options.services.claude-ping = {
        enable = lib.mkEnableOption "scheduled Claude keepalive ping";

        user = lib.mkOption {
          type = lib.types.str;
          description = "User whose Claude credentials the ping runs with.";
        };

        schedule = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [
            "Mon..Fri 07:00"
            "Mon..Fri 12:00"
          ];
          description = "OnCalendar expressions at which to ping.";
        };

        prompt = lib.mkOption {
          type = lib.types.str;
          default = "say just 'ok'";
          description = "Prompt sent to Claude. Kept trivial -- the point is the request, not the answer.";
        };

        model = lib.mkOption {
          type = lib.types.str;
          default = "haiku";
          description = "Model to ping with.";
        };

        retries = lib.mkOption {
          type = lib.types.int;
          default = 3;
          description = "Attempts before giving up, 30s apart. Covers a network that is not up yet after resume.";
        };
      };

      config = lib.mkIf cfg.enable {
        systemd.timers.claude-ping = {
          description = "Scheduled Claude keepalive ping";
          wantedBy = [ "timers.target" ];
          timerConfig = {
            OnCalendar = cfg.schedule;
            WakeSystem = true;
            # Catch up if the machine was powered off (rather than suspended)
            # at the scheduled time.
            Persistent = true;
            AccuracySec = "1min";
          };
        };

        systemd.services.claude-ping = {
          description = "Claude keepalive ping (network wait + inhibitor)";
          path = [ pkgs.networkmanager ];
          # Boot-time ordering only. network-online.target is not re-evaluated
          # on resume, so nm-online below is what actually gates the request.
          after = [ "network-online.target" ];
          wants = [ "network-online.target" ];
          serviceConfig = {
            Type = "oneshot";
            TimeoutStartSec = "10min";
          };
          script = ''
            # An RTC wake with the lid shut lets logind honour the lid switch
            # again once its 30s holdoff expires, which would suspend us
            # mid-request; the idle lock keeps hypridle's timers paused for the
            # duration.
            exec systemd-inhibit \
              --what=sleep:idle:handle-lid-switch \
              --who="claude-ping" \
              --why="Claude keepalive ping" \
              -- ${pkgs.bash}/bin/bash -c \
                'nm-online -q -t 60 || true; exec systemctl start --wait claude-ping-run.service'
          '';
        };

        systemd.services.claude-ping-run = {
          description = "Claude keepalive ping (runs as ${cfg.user})";
          path = [ pkgs.claude-code ];
          serviceConfig = {
            Type = "oneshot";
            User = cfg.user;
            TimeoutStartSec = "5min";
          };
          script = ''
            for attempt in $(seq 1 ${toString cfg.retries}); do
              if claude -p ${lib.escapeShellArg cfg.prompt} --model ${lib.escapeShellArg cfg.model}; then
                exit 0
              fi
              echo "claude ping attempt $attempt failed; retrying in 30s" >&2
              sleep 30
            done
            exit 1
          '';
        };
      };
    };
}

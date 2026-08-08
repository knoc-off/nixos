{ ... }:
{
  # Away policy for the TV box.
  #
  # A TV that nobody is watching should stop behaving like a live device: KDE
  # Connect shouldn't advertise itself to phones, Spotify shouldn't sit in the
  # Connect device list, and so on. This module owns the whole lifecycle --
  # including hypridle -- so the screen-off moment and the service-teardown
  # moment come from a single timeout and can't drift apart.
  #
  # Everything disposable hangs off `tv-active.target`. Things that must survive
  # in order to *notice* you came back (hyprland, hypridle, noctalia) stay
  # outside it, as does Firefox.
  #
  # Windowed apps are the exception: they are frozen rather than stopped, so
  # they go quiet on the network without their surface being destroyed.
  home =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.tv.away;
      systemctl = "${pkgs.systemd}/bin/systemctl";

      frozen = lib.filterAttrs (_: app: app.freeze) cfg.apps;
      frozenUnits = lib.mapAttrsToList (name: _: "${name}.service") frozen;

      # Frozen apps are deliberately kept out of tv-active.target: destroying a
      # window while the session is already idled makes Hyprland run
      # recheckIdleInhibitorStatus(), which ends in an unconditional
      # setInhibit(false). setInhibit has no change-guard, so it calls
      # update() -> reset() -> sendResumed() -- a resume event out of thin air,
      # with no input involved. hypridle then blanks-and-unblanks and restarts
      # everything it just stopped, on a loop the length of the timeout.
      # Freezing leaves the surface mapped, so the recheck never happens.
      appTarget = app: if app.freeze then "graphical-session.target" else "tv-active.target";

      awayScript = pkgs.writeShellScript "tv-away" ''
        ${systemctl} --user stop tv-active.target
        ${lib.optionalString (
          frozenUnits != [ ]
        ) "${systemctl} --user freeze ${lib.concatStringsSep " " frozenUnits}"}
      '';

      backScript = pkgs.writeShellScript "tv-back" ''
        ${lib.optionalString (
          frozenUnits != [ ]
        ) "${systemctl} --user thaw ${lib.concatStringsSep " " frozenUnits}"}
        ${systemctl} --user start tv-active.target
      '';
    in
    {
      options.tv.away = {
        timeout = lib.mkOption {
          type = lib.types.int;
          default = 2400;
          description = ''
            Seconds of input inactivity before the screen blanks and everything
            in tv-active.target is stopped.

            Audio playback suppresses this entirely via
            sway-audio-idle-inhibit, so music won't be cut off mid-track.
          '';
        };

        units = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          example = [ "kdeconnect" ];
          description = ''
            Names of *existing* systemd user services to place under
            tv-active.target. Each is stopped when the session goes idle and
            started again on the first input event.
          '';
        };

        apps = lib.mkOption {
          default = { };
          description = ''
            GUI apps that behave like session furniture: started with the
            session, stopped while away, restored on resume.

            These get real units so they have stable names to stop. Apps you
            open by hand from the launcher are not affected.
          '';
          type = lib.types.attrsOf (
            lib.types.submodule {
              options = {
                command = lib.mkOption {
                  type = lib.types.str;
                  description = "Absolute command to run.";
                };
                description = lib.mkOption {
                  type = lib.types.str;
                  default = "";
                  description = "Unit description.";
                };
                freeze = lib.mkOption {
                  type = lib.types.bool;
                  default = false;
                  description = ''
                    Suspend the app with the cgroup freezer instead of stopping
                    it. Use this for anything with a window: killing a client
                    while the session is idled makes Hyprland emit a bogus
                    resume, which immediately undoes the teardown.

                    A frozen app cannot run, so it drops off the network (a
                    frozen Spotify stops advertising itself as a Connect
                    device), but it keeps its memory and its window.
                  '';
                };
              };
            }
          );
        };
      };

      config = {
        systemd.user.targets.tv-active = {
          Unit = {
            Description = "TV session is actively in use";
            PartOf = [ "graphical-session.target" ];
            After = [ "graphical-session.target" ];
          };
          Install.WantedBy = [ "graphical-session.target" ];
        };

        systemd.user.services = lib.mkMerge [
          # Wrapped as a real unit (rather than pointed to directly from
          # hypridle and tv-remote both) so there's one canonical away path --
          # anything that wants to put the TV to sleep runs this unit.
          {
            tv-away = {
              Unit.Description = "Enter TV away state";
              Service = {
                Type = "oneshot";
                ExecStart = awayScript;
              };
            };
          }

          # Retarget services that already exist (kdeconnect et al). PartOf is a
          # list of primitives in home-manager's unit freeform type, so this
          # concatenates with whatever the upstream module set. WantedBy must be
          # mkForce'd rather than appended: if graphical-session.target stayed in
          # the list, `systemctl start tv-active.target` would not pull the
          # service back up on resume.
          (lib.genAttrs cfg.units (_: {
            Unit.PartOf = [ "tv-active.target" ];
            Install.WantedBy = lib.mkForce [ "tv-active.target" ];
          }))

          (lib.mapAttrs (name: app: {
            Unit = {
              Description = if app.description != "" then app.description else name;
              PartOf = [ (appTarget app) ];
              After = [
                "graphical-session.target"
              ] ++ lib.optional (!app.freeze) "tv-active.target";
            };
            Install.WantedBy = [ (appTarget app) ];
            Service = {
              ExecStart = app.command;
              Slice = "app-graphical.slice";
              # A clean exit means you closed the window on purpose -- leave it
              # closed until the next resume. Only crashes get restarted.
              Restart = "on-failure";
              RestartSec = 5;
            };
          }) cfg.apps)
        ];

        # No lock, no suspend -- blank the panel and drop the disposable
        # services. Silent/paused fullscreen video is covered by the
        # idle_inhibit window rule in hyprland-tv's lua config.
        services.hypridle = {
          enable = true;
          settings = {
            general = {
              after_sleep_cmd = "hyprctl dispatch 'hl.dsp.dpms({ action = \"enable\" })'";
            };

            listener = [
              {
                timeout = cfg.timeout;
                on-timeout = "hyprctl dispatch 'hl.dsp.dpms({ action = \"disable\" })'";
                on-resume = "hyprctl dispatch 'hl.dsp.dpms({ action = \"enable\" })'";
              }
              {
                timeout = cfg.timeout;
                on-timeout = "${systemctl} --user start tv-away.service";
                on-resume = "${backScript}";
              }
            ];
          };
        };
      };
    };
}

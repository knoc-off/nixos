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
              PartOf = [ "tv-active.target" ];
              After = [
                "graphical-session.target"
                "tv-active.target"
              ];
            };
            Install.WantedBy = [ "tv-active.target" ];
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
                on-timeout = "${systemctl} --user stop tv-active.target";
                on-resume = "${systemctl} --user start tv-active.target";
              }
            ];
          };
        };
      };
    };
}

# Ship TLS cert/key files to a remote host over SSH whenever they change.
# Used to copy ACME-renewed certs from a hub to leaf hosts that serve the
# same hostname locally (for example, a home gateway terminating TLS on
# LAN so clients don't need the VPN). Pairs with the cert-receiver module
# on the destination host.
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.cert-sync;

  # Space-separated, individually quoted absolute paths for rsync args.
  # Values come from nix config, not user input, so injection is not a
  # concern but we still quote for safety.
  certSources =
    lib.concatMapStringsSep " "
    (c: ''"${c.certFile}" "${c.keyFile}"'')
    cfg.certs;

  dest = "${cfg.destination.user}@${cfg.destination.host}";

  # Unit-name-safe variant of a cert name (dots are legal in systemd
  # unit names but awkward; swap them for dashes).
  sanitize = name: lib.replaceStrings ["."] ["-"] name;

  syncScript = pkgs.writeShellApplication {
    name = "cert-sync";
    runtimeInputs = with pkgs; [openssh rsync];
    text = ''
      known="${cfg.stateDir}/known_hosts"
      ssh_opts="-i ${cfg.destination.sshKeyFile} -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=$known -o ConnectTimeout=15 -o BatchMode=yes"

      # Bootstrap guard: on first boot the source certs may not exist yet
      # (ACME hasn't issued). Exit cleanly so the unit doesn't flap.
      for f in ${certSources}; do
        if [ ! -f "$f" ]; then
          echo "cert-sync: source missing ($f), skipping"
          exit 0
        fi
      done

      # shellcheck disable=SC2086
      # Target is ./ because the receiver runs rrsync -wo <dir>, which
      # locks the root to its configured path and treats any client-
      # supplied path as relative to it.
      rsync -a --chmod=F640 \
        -e "ssh $ssh_opts" \
        ${certSources} \
        ${dest}:./
      ${lib.optionalString (cfg.destination.reloadCommand != null) ''

        # shellcheck disable=SC2086
        ssh $ssh_opts ${dest} ${cfg.destination.reloadCommand}
      ''}
    '';
  };
in {
  options.services.cert-sync = {
    enable = lib.mkEnableOption "sync TLS certs to a remote host on change";

    destination = {
      host = lib.mkOption {
        type = lib.types.str;
        description = "SSH destination (IP or hostname).";
      };
      user = lib.mkOption {
        type = lib.types.str;
        default = "root";
        description = "SSH user on the destination.";
      };
      sshKeyFile = lib.mkOption {
        type = lib.types.str;
        description = "Path to the SSH private key file (usually a sops secret path).";
      };
      reloadCommand = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = ''
          Keyword the destination's forced-command dispatch understands
          to trigger a service reload after a successful sync. Null to
          skip the reload step entirely.
        '';
        example = "reload-caddy";
      };
    };

    certs = lib.mkOption {
      default = [];
      description = ''
        Certs to sync. Any change to any certFile triggers rsync of the
        full list in a single invocation (rsync is idempotent). Each
        cert produces its own path unit.
      '';
      type = lib.types.listOf (lib.types.submodule {
        options = {
          name = lib.mkOption {
            type = lib.types.str;
            description = "Display name, used for log lines and unit naming.";
          };
          certFile = lib.mkOption {
            type = lib.types.str;
            description = "Absolute path on this host to the cert file.";
          };
          keyFile = lib.mkOption {
            type = lib.types.str;
            description = "Absolute path on this host to the private key file.";
          };
        };
      });
    };

    fallbackSchedule = lib.mkOption {
      type = lib.types.str;
      default = "weekly";
      description = ''
        OnCalendar expression for the backstop timer. Fires in addition
        to the path-based event trigger; catches the case where the
        sender was down during a renewal and the inotify event was missed.
      '';
    };

    stateDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/cert-sync";
      description = "Local state directory (stores known_hosts).";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.tmpfiles.rules = [
      "d ${cfg.stateDir} 0700 root root -"
    ];

    systemd.services.cert-sync = {
      description = "Push TLS certs to ${dest}";
      after = ["network-online.target"];
      wants = ["network-online.target"];
      serviceConfig = {
        Type = "oneshot";
        User = "root";
        ExecStart = "${syncScript}/bin/cert-sync";
      };
    };

    systemd.paths =
      lib.listToAttrs (map (c: {
          name = "cert-sync-${sanitize c.name}";
          value = {
            description = "Watch ${c.name} cert for changes";
            wantedBy = ["multi-user.target"];
            pathConfig = {
              PathChanged = c.certFile;
              Unit = "cert-sync.service";
            };
          };
        })
        cfg.certs);

    systemd.timers.cert-sync = {
      description = "Backstop timer for cert-sync in case a path event is missed";
      wantedBy = ["timers.target"];
      timerConfig = {
        OnCalendar = cfg.fallbackSchedule;
        Persistent = true;
        Unit = "cert-sync.service";
      };
    };
  };
}

# Receive TLS cert files from a cert-sync sender. Registers a forced-
# command SSH key for root that either accepts an rsync drop (via
# rrsync, which enforces destination path and write-only mode) or
# reloads a systemd unit. Any other command is denied. Pairs with the
# cert-sync module on the sender host.
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.cert-receiver;

  dispatchScript = pkgs.writeShellApplication {
    name = "cert-receiver-dispatch";
    runtimeInputs = with pkgs; [rrsync systemd];
    text = ''
      cmd="''${SSH_ORIGINAL_COMMAND:-}"
      case "$cmd" in
        "rsync --server"*)
          # rrsync enforces -wo: write-only, destination-locked.
          # We don't trust the glob match; we trust rrsync.
          exec rrsync -wo ${cfg.path}
          ;;
        ${lib.optionalString (cfg.reloadUnit != null) ''
        ${cfg.reloadCommandName})
          exec systemctl reload ${cfg.reloadUnit}
          ;;''}
        *)
          echo "cert-receiver: refused command: $cmd" >&2
          exit 1
          ;;
      esac
    '';
  };
in {
  options.services.cert-receiver = {
    enable = lib.mkEnableOption "receive TLS certs from a cert-sync sender";

    path = lib.mkOption {
      type = lib.types.str;
      description = ''
        Directory where incoming certs are written. Created with the
        configured owner/group/mode via tmpfiles before any sender can
        push. rrsync locks all writes into exactly this path.
      '';
    };

    owner = lib.mkOption {
      type = lib.types.str;
      default = "root";
      description = "Owner of the receive directory.";
    };

    group = lib.mkOption {
      type = lib.types.str;
      default = "root";
      description = "Group of the receive directory.";
    };

    mode = lib.mkOption {
      type = lib.types.str;
      default = "0750";
      description = "Mode of the receive directory.";
    };

    authorizedKey = lib.mkOption {
      type = lib.types.str;
      description = "Public key of the cert-sync sender allowed to push here.";
      example = "ssh-ed25519 AAAA... cert-sync@hub";
    };

    reloadUnit = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        systemd unit to reload when the sender sends the reload keyword.
        Null disables the reload branch entirely; the dispatch script
        then only accepts rsync drops.
      '';
      example = "caddy.service";
    };

    reloadCommandName = lib.mkOption {
      type = lib.types.str;
      default = "reload-receiver";
      description = "Keyword the sender passes over SSH to trigger a reload.";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.tmpfiles.rules = [
      "d ${cfg.path} ${cfg.mode} ${cfg.owner} ${cfg.group} -"
    ];

    users.users.root.openssh.authorizedKeys.keys = [
      ''restrict,command="${dispatchScript}/bin/cert-receiver-dispatch" ${cfg.authorizedKey}''
    ];
  };
}

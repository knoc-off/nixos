# Minecraft world snapshots -- hourly, quiesced btrfs snapshots of /srv/minecraft.
#
# Why quiesce: Minecraft holds the world in memory and autosaves lazily, so a
# bare snapshot is only crash-consistent and can be missing everything built
# since the last autosave. `save-off` + `save-all flush` forces a complete,
# settled world to disk first. That matters more than usual here because these
# snapshots double as timelapse frames, and a frame that silently lags the live
# world is worse than a missing one.
#
# Retention `48h 30d *w`: hourly for two days, daily for a month, weekly
# forever. `*w` subsumes monthly and yearly -- keeping every weekly forever
# already preserves one snapshot per week back to the beginning of time.
#
# The cost is smaller than it looks: btrfs snapshots only pin data that is
# *overwritten*. Generating new terrain is new data and is nearly free; only
# edits to already-generated chunks accrue. Steady state is ~130 snapshots,
# growing 52/year, which is well within what btrfs handles comfortably.
#
# The hourly instance deliberately has no `target`. btrbk skips snapshot
# deletion entirely whenever a configured target is unreachable (btrbk(1),
# "run", step 4), so a USB target in the same config would silently stop local
# pruning for as long as the drive is missing. The USB copy is therefore a
# second instance (minecraft-usb) that only sends existing snapshots and never
# creates or deletes any on the NVMe.
#
# The hourly snapshots share a disk with the world, so they defend against
# mistakes and corruption, not drive failure. The USB copy covers the NVMe
# dying, but sits in the same box, so not theft, fire or a bad PSU.
{
  self,
  config,
  pkgs,
  ...
}:
let
  serverName = "inkwell";
  serverUnit = "minecraft-server-${serverName}.service";
  rconPort = 25575;
  dataDir = "/srv/minecraft";
  snapshotDir = "${dataDir}/.snapshots";
  backupDir = "/mnt/backup";

  envFile = config.sops.templates."minecraft.env".path;
  rcon = self.packages.${pkgs.stdenv.hostPlatform.system}.rcon-cli;

  # Upstream builds cmd/gorcon, so the binary is not named after the package.
  rconCmd = ''${rcon}/bin/gorcon -a 127.0.0.1:${toString rconPort} -p "$RCON_PASSWORD"'';

  # Both scripts run as root via the `+` prefix on Exec*, which is what lets
  # them read the 0400 root-owned sops env file while btrbk itself stays
  # unprivileged.
  quiesce = pkgs.writeShellScript "minecraft-snapshot-quiesce" ''
    set -uo pipefail

    # A stopped server holds nothing in memory, so its on-disk world is already
    # settled.
    ${config.systemd.package}/bin/systemctl is-active --quiet ${serverUnit} || exit 0

    set -a; . ${envFile}; set +a

    # Degrade rather than abort. A crash-consistent snapshot is still worth
    # having -- btrfs snapshots are atomic and Anvil survives power loss --
    # whereas failing here would take the entire snapshot regime down with RCON.
    if ! ${rconCmd} "save-off"; then
      echo "quiesce: RCON save-off failed, taking a crash-consistent snapshot" >&2
      exit 0
    fi
    ${rconCmd} "save-all flush" \
      || echo "quiesce: save-all flush failed, snapshot may lag the live world" >&2
    ${pkgs.coreutils}/bin/sync
  '';

  unquiesce = pkgs.writeShellScript "minecraft-snapshot-unquiesce" ''
    set -uo pipefail

    if ${config.systemd.package}/bin/systemctl is-active --quiet ${serverUnit}; then
      set -a; . ${envFile}; set +a
      ${rconCmd} "save-on" \
        || echo "unquiesce: RCON save-on FAILED, autosave may still be off" >&2
    fi

    # ExecStopPost must never mask the outcome of the snapshot run itself.
    exit 0
  '';
in
{
  # `v` creates a btrfs subvolume where the filesystem supports one, which keeps
  # the snapshot directory out of the snapshots themselves. It degrades to a
  # plain directory harmlessly -- that would only leave an empty stub dir inside
  # each snapshot.
  systemd.tmpfiles.rules = [
    "v ${snapshotDir} 0755 root root -"
  ];

  services.btrbk.instances.minecraft = {
    onCalendar = "hourly";
    # No target exists, so `run` and `snapshot` are equivalent today; being
    # explicit means adding one later cannot start sending unannounced.
    snapshotOnly = true;
    settings = {
      # Defaults to "all", which silently voids snapshot_preserve entirely.
      snapshot_preserve_min = "2d";
      snapshot_preserve = "48h 30d *w";
      # Skip snapshots when the world has not changed, so an idle or stopped
      # server does not accumulate identical entries.
      snapshot_create = "onchange";
      # Unambiguous across DST changes, which matters for snapshots kept forever.
      timestamp_format = "long-iso";
      # systemd already serialises the timer; this guards manual invocations.
      lockfile = "/var/lib/btrbk/minecraft.lock";
      subvolume.${dataDir} = {
        snapshot_dir = snapshotDir;
        snapshot_name = "minecraft";
      };
    };
  };

  # Daily copy of the snapshots above to the USB drive (/mnt/backup, set up in
  # default.nix). Incremental: btrbk picks the newest snapshot both sides share
  # as parent, and the weekly ones kept forever above guarantee one exists
  # however long the drive was away.
  services.btrbk.instances.minecraft-usb = {
    # Off the hour, so it never races the hourly instance pruning a snapshot
    # mid-send.
    onCalendar = "*-*-* 04:30:00";
    settings = {
      # Never touch the NVMe side: creation and pruning belong to the hourly
      # instance.
      snapshot_create = "no";
      snapshot_preserve_min = "all";
      target_preserve_min = "2d";
      target_preserve = "30d *w";
      timestamp_format = "long-iso";
      lockfile = "/var/lib/btrbk/minecraft-usb.lock";
      subvolume.${dataDir} = {
        snapshot_dir = snapshotDir;
        snapshot_name = "minecraft";
        # The drive's root, not a subdir: btrbk never creates target dirs, and
        # a tmpfiles one would land on the root fs whenever the drive is away.
        target = backupDir;
      };
    };
  };

  systemd.services.btrbk-minecraft = {
    onFailure = [ "btrbk-failure@minecraft.service" ];
    serviceConfig = {
      ExecStartPre = "+${quiesce}";
      ExecStopPost = "+${unquiesce}";
    };
    # Without the subvolume mounted there is no world to snapshot, and the
    # snapshot dir would be created on the root filesystem instead.
    unitConfig.RequiresMountsFor = dataDir;
  };

  systemd.services.btrbk-minecraft-usb = {
    onFailure = [ "btrbk-failure@minecraft-usb.service" ];
    # A missing drive fails this unit (and alerts) instead of receiving into
    # an empty /mnt/backup on the root filesystem.
    unitConfig.RequiresMountsFor = [
      dataDir
      backupDir
    ];
  };

  systemd.services."btrbk-failure@" = {
    description = "Report a failed btrbk-%i run to ntfy";
    serviceConfig = {
      Type = "oneshot";
      LoadCredential = "ntfy-token:${config.sops.secrets."services/ntfy/publish-token".path}";
    };
    scriptArgs = "%i";
    script = ''
      ${pkgs.curl}/bin/curl -fsS \
        -H "Authorization: Bearer $(cat "$CREDENTIALS_DIRECTORY/ntfy-token")" \
        -H "Title: btrbk-$1 failed" \
        -H "Priority: high" \
        -H "Tags: warning" \
        -d "btrbk-$1 failed on ${config.networking.hostName}. Check journalctl -u btrbk-$1" \
        https://ntfy.niko.ink/alerts
    '';
  };

  # Snapshots kept forever are only as good as the bytes under them, and scrub
  # is what surfaces silent corruption. Every NVMe subvolume lives on one
  # filesystem, so scrubbing / covers the world too; the default (every btrfs
  # mount point) would scrub the same device repeatedly. On the single-disk USB
  # drive scrub can only detect, not repair -- which is still the signal that
  # the backup has rotted.
  services.btrfs.autoScrub = {
    enable = true;
    interval = "monthly";
    fileSystems = [
      "/"
      backupDir
    ];
  };
}

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
# There is deliberately no `target` section here. btrbk skips snapshot deletion
# entirely whenever a configured target is unreachable (btrbk(1), "run", step
# 4), so folding the planned USB archive into this config would silently stop
# local pruning for as long as the stick stays unplugged. That archive needs its
# own config file, not another section in this one.
#
# These snapshots share a disk with the world, so they defend against mistakes
# and corruption, not against drive failure.
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

  systemd.services.btrbk-minecraft = {
    onFailure = [ "btrbk-minecraft-failure.service" ];
    serviceConfig = {
      ExecStartPre = "+${quiesce}";
      ExecStopPost = "+${unquiesce}";
    };
    # Without the subvolume mounted there is no world to snapshot, and the
    # snapshot dir would be created on the root filesystem instead.
    unitConfig.RequiresMountsFor = dataDir;
  };

  systemd.services.btrbk-minecraft-failure = {
    description = "Report a failed Minecraft snapshot run to ntfy";
    serviceConfig = {
      Type = "oneshot";
      LoadCredential = "ntfy-token:${config.sops.secrets."services/ntfy/publish-token".path}";
    };
    script = ''
      ${pkgs.curl}/bin/curl -fsS \
        -H "Authorization: Bearer $(cat "$CREDENTIALS_DIRECTORY/ntfy-token")" \
        -H "Title: Minecraft snapshot failed" \
        -H "Priority: high" \
        -H "Tags: warning" \
        -d "btrbk-minecraft failed on ${config.networking.hostName}. Check journalctl -u btrbk-minecraft" \
        https://ntfy.niko.ink/alerts
    '';
  };

  # Snapshots kept forever are only as good as the bytes under them, and scrub
  # is what surfaces silent corruption. Every subvolume lives on one filesystem,
  # so scrubbing / covers the world too; the default (every btrfs mount point)
  # would scrub the same device repeatedly.
  services.btrfs.autoScrub = {
    enable = true;
    interval = "monthly";
    fileSystems = [ "/" ];
  };
}

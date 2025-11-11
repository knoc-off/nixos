{
  config,
  pkgs,
  lib,
  osConfig,
  ...
}: {
  programs.rclone = {
    enable = true;

    remotes = {
      webdav = {
        config = {
          type = "webdav";
          url = "https://sync.niko.ink";
          vendor = "other";
          user = "sync-user";
        };
        secrets = {
          pass = "/etc/rclone-webdav-pass";
        };
      };
    };
  };

  # Systemd user service for auto-sync
  systemd.user.services.rclone-sync = {
    Unit = {
      Description = "Rclone bidirectional sync";
      After = ["network-online.target"];
    };

    Service = {
      Type = "oneshot";
      ExecStart = "${pkgs.rclone}/bin/rclone bisync %h/Sync webdav: --size-only --verbose --create-empty-src-dirs --resilient --recover --max-delete 10 --conflict-loser delete";
    };
  };

  # Timer to run sync every 15 minutes
  systemd.user.timers.rclone-sync = {
    Unit = {
      Description = "Rclone sync timer";
    };

    Timer = {
      OnBootSec = "2min";
      OnUnitActiveSec = "15min";
      Persistent = true;
    };

    Install = {
      WantedBy = ["timers.target"];
    };
  };

  # Create sync directory
  home.activation.createSyncDir = lib.hm.dag.entryAfter ["writeBoundary"] ''
    mkdir -p ~/Sync/{Documents,Photos,Books,Obsidian}
  '';
}

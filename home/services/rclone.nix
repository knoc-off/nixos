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

  systemd.user.services.rclone-sync = {
    Unit = {
      Description = "Rclone bidirectional sync";
      After = ["network-online.target"];
    };

    Service = {
      Type = "oneshot";
      ExecStart = let
        syncScript = pkgs.writeShellScript "rclone-sync" ''
          LISTING_PATH="$HOME/.cache/rclone/bisync/home_knoff_Sync..webdav_.path1.lst"

          if [ ! -f "$LISTING_PATH" ]; then
            echo "First run detected, performing initial --resync"
            ${pkgs.rclone}/bin/rclone bisync $HOME/Sync webdav: --resync --size-only --verbose --create-empty-src-dirs --max-delete 10 --conflict-loser delete
          else
            ${pkgs.rclone}/bin/rclone bisync $HOME/Sync webdav: --size-only --verbose --create-empty-src-dirs --resilient --recover --max-delete 10 --conflict-loser delete
          fi
        '';
      in "${syncScript}";
    };
  };

  systemd.user.timers.rclone-sync = {
    Unit = {
      Description = "Rclone sync timer";
    };

    Timer = {
      OnBootSec = "2min";
      OnUnitActiveSec = "5min";
      Persistent = true;
    };

    Install = {
      WantedBy = ["timers.target"];
    };
  };

  # Create sync directory
  home.activation.createSyncDir = lib.hm.dag.entryAfter ["writeBoundary"] ''
    mkdir -p ~/Sync/{Books,Obsidian}
  '';
}

{ inputs, ... }: {
  home = { pkgs, ... }:
  let
    upkgs = import inputs.nixpkgs-unstable { inherit (pkgs) system; config = pkgs.config; };
    claude = "${upkgs.claude-code}/bin/claude";
    jq = "${pkgs.jq}/bin/jq";
    systemctl = "${pkgs.systemd}/bin/systemctl";
    systemd-run = "${pkgs.systemd}/bin/systemd-run";
    date = "${pkgs.coreutils}/bin/date";

    schedulerScript = pkgs.writeShellScript "claude-token-scheduler" ''
      set -euo pipefail

      CREDS="$HOME/.claude/.credentials.json"
      BUFFER=300 # refresh 5 minutes before expiry

      if [ ! -f "$CREDS" ]; then
        echo "No credentials file, refreshing now"
        ${systemctl} --user start claude-token-refresh.service
        exit 0
      fi

      expires_ms=$(${jq} -r '.claudeAiOauth.expiresAt' "$CREDS")
      if [ -z "$expires_ms" ] || [ "$expires_ms" = "null" ]; then
        echo "Cannot read expiresAt, refreshing now"
        ${systemctl} --user start claude-token-refresh.service
        exit 0
      fi

      expires_s=$((expires_ms / 1000))
      now_s=$(${date} +%s)
      delay=$(( expires_s - now_s - BUFFER ))

      # Clean up any previously scheduled transient timer
      ${systemctl} --user stop claude-token-refresh-run.timer 2>/dev/null || true
      ${systemctl} --user reset-failed claude-token-refresh-run.service 2>/dev/null || true

      if [ "$delay" -le 0 ]; then
        echo "Token expired or expiring within ''${BUFFER}s, refreshing now"
        ${systemctl} --user start claude-token-refresh.service
      else
        echo "Scheduling refresh in ''${delay}s (at $(${date} -d "@$((now_s + delay))" '+%Y-%m-%d %H:%M:%S'))"
        ${systemd-run} --user \
          --on-active="''${delay}s" \
          --unit=claude-token-refresh-run \
          --description="Scheduled Claude token refresh" \
          -- ${systemctl} --user start claude-token-refresh.service
      fi
    '';

    refreshScript = pkgs.writeShellScript "claude-token-refresh" ''
      set -euo pipefail
      echo "Refreshing Claude OAuth token..."
      ${claude} -p "say just 'ok'" --model 'haiku'
      echo "Token refreshed"
    '';
  in {
    # Service A: reads expiry, schedules the refresh
    systemd.user.services.claude-token-scheduler = {
      Unit.Description = "Schedule Claude OAuth token refresh based on expiry";
      Service = {
        Type = "oneshot";
        ExecStart = schedulerScript;
      };
    };

    # Fallback timer: kicks off the chain on login + periodic safety net
    # Persistent=true ensures it fires after sleep/resume if a run was missed
    systemd.user.timers.claude-token-scheduler = {
      Unit.Description = "Fallback timer for Claude token scheduler";
      Timer = {
        OnStartupSec = "30s";
        OnUnitActiveSec = "2h";
        Persistent = true;
      };
      Install.WantedBy = [ "timers.target" ];
    };

    # Service B: runs claude to refresh the token, then leapfrogs back to A
    systemd.user.services.claude-token-refresh = {
      Unit.Description = "Refresh Claude CLI OAuth token";
      Service = {
        Type = "oneshot";
        ExecStart = refreshScript;
        # Retry on failure (network down, etc.) — up to 5 attempts, 2 min apart
        Restart = "on-failure";
        RestartSec = "30s";
      };
      Unit.StartLimitIntervalSec = 600; # 10 min window
      Unit.StartLimitBurst = 20;        # max 20 attempts (every 30s for 10 min)
      # Leapfrog: on success, re-trigger scheduler to read new expiry
      # (only runs after final successful ExecStart, not on retried failures)
      Service.ExecStartPost = "${systemctl} --user start claude-token-scheduler.service";
    };
  };
}

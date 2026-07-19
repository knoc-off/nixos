# KitchenOwl meal-plan notifier.
#
# A separate, timer-driven companion to kitchenowl-notify. Runs only at the
# configured meal times (no continuous polling). Each run does two things:
#   1. Notifies about recipes newly added to the meal plan (diff vs baseline).
#   2. Reminds about recipes planned for *today* whose meal slot matches the
#      current time. Slot is taken from a recipe's breakfast/lunch/dinner tag;
#      untagged recipes default to the dinner (evening) slot.
#
# Auth: same KitchenOwl + ntfy tokens as kitchenowl-notify, read at exec time
# via systemd LoadCredential.
{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.services.kitchenowl-meal-plan;

  pollScript =
    pkgs.writers.writePython3Bin "kitchenowl-meal-plan" {
      flakeIgnore = ["E501" "W503"];
    }
    ./kitchenowl-meal-plan.py;
in {
  options.services.kitchenowl-meal-plan = {
    enable = mkEnableOption "KitchenOwl meal-plan notifier";

    householdId = mkOption {
      type = types.int;
      description = "KitchenOwl household ('home') id whose meal plan is watched.";
      example = 1;
    };

    apiBase = mkOption {
      type = types.str;
      default = "http://127.0.0.1:3043";
      description = "Base URL of the KitchenOwl backend (no trailing slash). The API lives under /api.";
    };

    ntfy = {
      url = mkOption {
        type = types.str;
        default = "http://127.0.0.1:2586";
        description = "Base URL of the ntfy server (no trailing slash).";
      };
      topic = mkOption {
        type = types.str;
        default = "kitchenowl";
        description = "ntfy topic to publish meal-plan notifications to.";
      };
    };

    times = {
      breakfast = mkOption {
        type = types.str;
        default = "08:00";
        description = "Time (systemd OnCalendar) for the breakfast reminder.";
      };
      lunch = mkOption {
        type = types.str;
        default = "12:00";
        description = "Time (systemd OnCalendar) for the lunch reminder.";
      };
      dinner = mkOption {
        type = types.str;
        default = "18:00";
        description = "Time (systemd OnCalendar) for the dinner reminder. Also the slot for untagged recipes.";
      };
    };

    apiTokenFile = mkOption {
      type = types.path;
      description = "Path (sops secret) to a file whose first line is a KitchenOwl long-lived token.";
    };

    ntfyTokenFile = mkOption {
      type = types.path;
      description = "Path (sops secret) to a file whose first line is an ntfy token with write access to `ntfy.topic`.";
    };
  };

  config = mkIf cfg.enable {
    systemd.services.kitchenowl-meal-plan = {
      description = "KitchenOwl meal-plan notifier";
      after = ["network-online.target"];
      wants = ["network-online.target"];

      environment = {
        KO_API_BASE = cfg.apiBase;
        KO_HOUSEHOLD_ID = toString cfg.householdId;
        KO_NTFY_URL = cfg.ntfy.url;
        KO_NTFY_TOPIC = cfg.ntfy.topic;
        KO_TIME_BREAKFAST = cfg.times.breakfast;
        KO_TIME_LUNCH = cfg.times.lunch;
        KO_TIME_DINNER = cfg.times.dinner;
      };

      serviceConfig = {
        Type = "oneshot";
        ExecStart = getExe pollScript;

        DynamicUser = true;
        StateDirectory = "kitchenowl-meal-plan";
        LoadCredential = [
          "api-token:${toString cfg.apiTokenFile}"
          "ntfy-token:${toString cfg.ntfyTokenFile}"
        ];

        # Hardening.
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
        RestrictSUIDSGID = true;
        RestrictNamespaces = true;
        LockPersonality = true;
        RestrictAddressFamilies = ["AF_INET" "AF_INET6" "AF_UNIX"];
      };
    };

    systemd.timers.kitchenowl-meal-plan = {
      description = "KitchenOwl meal-plan reminder timer";
      wantedBy = ["timers.target"];
      timerConfig = {
        OnCalendar = [cfg.times.breakfast cfg.times.lunch cfg.times.dinner];
        # A missed meal reminder is stale; don't catch up on boot.
        Persistent = false;
      };
    };
  };
}

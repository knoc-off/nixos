# KitchenOwl shopping-list change notifier.
#
# Polls a household's shopping lists over the KitchenOwl API and, once
# activity has *settled* (a poll cycle with no change), publishes a single
# batched summary of adds/removes to ntfy. Debounce avoids a notification
# storm while someone is actively editing the list.
#
# Auth: a long-lived KitchenOwl token (Bearer) + an ntfy publish token.
# Both are read at exec time via systemd LoadCredential so they never land
# in argv, the environment, or the unit file. Config is passed via the
# environment; the script itself is static (pure Python stdlib, no deps).
{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.services.kitchenowl-notify;

  pollScript = pkgs.writers.writePython3Bin "kitchenowl-notify" {
    flakeIgnore = ["E501"];
  } ''
    import json
    import os
    import urllib.request


    def read_credential(name):
        creds = os.environ["CREDENTIALS_DIRECTORY"]
        with open(os.path.join(creds, name)) as f:
            return f.readline().strip()


    def fetch_items(api_base, household_id, token):
        url = f"{api_base}/api/household/{household_id}/shoppinglist"
        req = urllib.request.Request(
            url, headers={"Authorization": f"Bearer {token}"}
        )
        with urllib.request.urlopen(req, timeout=20) as resp:
            data = json.load(resp)
        # A set of (list_name, item_name) pairs across all lists, plus the
        # name of the default list (lowest id) so it can be omitted in output.
        items = set()
        default_list_name = None
        min_id = None
        for lst in data:
            list_name = lst.get("name", "")
            list_id = lst.get("id")
            if list_id is not None and (min_id is None or list_id < min_id):
                min_id = list_id
                default_list_name = list_name
            for item in lst.get("items") or []:
                items.add((list_name, item.get("name", "")))
        return items, default_list_name


    def load_state(path):
        if not os.path.exists(path):
            return None
        with open(path) as f:
            return {tuple(pair) for pair in json.load(f)}


    def save_state(path, items):
        tmp = path + ".tmp"
        with open(tmp, "w") as f:
            json.dump(sorted(items), f)
        os.replace(tmp, path)


    def publish(ntfy_url, topic, title, token, message, click_url):
        req = urllib.request.Request(
            f"{ntfy_url}/{topic}",
            data=message.encode("utf-8"),
            headers={
                "Authorization": f"Bearer {token}",
                "Title": title,
                "Click": click_url,
                "Tags": "shopping_cart",
            },
            method="POST",
        )
        with urllib.request.urlopen(req, timeout=20) as resp:
            resp.read()


    def main():
        api_base = os.environ["KO_API_BASE"]
        household_id = os.environ["KO_HOUSEHOLD_ID"]
        ntfy_url = os.environ["KO_NTFY_URL"]
        topic = os.environ["KO_NTFY_TOPIC"]
        title = os.environ["KO_NTFY_TITLE"]
        state_dir = os.environ.get("STATE_DIRECTORY", "/var/lib/kitchenowl-notify")

        baseline_path = os.path.join(state_dir, "baseline.json")
        last_seen_path = os.path.join(state_dir, "last_seen.json")

        api_token = read_credential("api-token")
        ntfy_token = read_credential("ntfy-token")

        current, default_list = fetch_items(api_base, household_id, api_token)

        click_url = f"https://app.kitchenowl.org/household/{household_id}/items"

        baseline = load_state(baseline_path)
        if baseline is None:
            # First run: establish a silent baseline, no notification.
            save_state(baseline_path, current)
            save_state(last_seen_path, current)
            print(f"kitchenowl-notify: baseline established ({len(current)} items)")
            return

        last_seen = load_state(last_seen_path) or set()

        # Debounce: only notify once activity has settled (state identical to
        # the previous poll) AND it differs from the last-notified baseline.
        settled = current == last_seen
        if settled and current != baseline:
            added = current - baseline
            removed = baseline - current

            def fmt(prefix, lst, item):
                if lst and lst != default_list:
                    return f"{prefix} {item} ({lst})"
                return f"{prefix} {item}"

            lines = [fmt("🟢", lst, item) for lst, item in sorted(added)]
            lines += [fmt("🔴", lst, item) for lst, item in sorted(removed)]
            if lines:
                publish(
                    ntfy_url, topic, title, ntfy_token, "\n".join(lines), click_url
                )
                print("kitchenowl-notify: summary sent")
            save_state(baseline_path, current)

        save_state(last_seen_path, current)


    if __name__ == "__main__":
        main()
  '';
in {
  options.services.kitchenowl-notify = {
    enable = mkEnableOption "KitchenOwl shopping-list change notifier";

    householdId = mkOption {
      type = types.int;
      description = "KitchenOwl household ('home') id whose shopping lists are watched.";
      example = 1;
    };

    apiBase = mkOption {
      type = types.str;
      default = "http://127.0.0.1:3043";
      description = "Base URL of the KitchenOwl backend (no trailing slash). The API lives under /api.";
    };

    interval = mkOption {
      type = types.str;
      default = "60s";
      description = "Poll cadence, in systemd `OnUnitActiveSec` syntax.";
    };

    ntfy = {
      url = mkOption {
        type = types.str;
        default = "http://127.0.0.1:2586";
        description = "Base URL of the ntfy server (no trailing slash).";
      };
      topic = mkOption {
        type = types.str;
        default = "shopping-list";
        description = "ntfy topic to publish shopping-list change summaries to.";
      };
      title = mkOption {
        type = types.str;
        default = "Shopping list changes";
        description = "Title header for the ntfy notification.";
      };
    };

    apiTokenFile = mkOption {
      type = types.path;
      description = ''
        Path (sops secret) to a file whose first line is a KitchenOwl
        long-lived token. Used as a Bearer token against the API.
      '';
    };

    ntfyTokenFile = mkOption {
      type = types.path;
      description = ''
        Path (sops secret) to a file whose first line is an ntfy token with
        write access to `ntfy.topic`. Used as a Bearer token when publishing.
      '';
    };
  };

  config = mkIf cfg.enable {
    systemd.services.kitchenowl-notify = {
      description = "KitchenOwl shopping-list change notifier";
      after = ["network-online.target"];
      wants = ["network-online.target"];
      # Not wantedBy: the timer owns activation.

      environment = {
        KO_API_BASE = cfg.apiBase;
        KO_HOUSEHOLD_ID = toString cfg.householdId;
        KO_NTFY_URL = cfg.ntfy.url;
        KO_NTFY_TOPIC = cfg.ntfy.topic;
        KO_NTFY_TITLE = cfg.ntfy.title;
      };

      serviceConfig = {
        Type = "oneshot";
        ExecStart = getExe pollScript;

        DynamicUser = true;
        StateDirectory = "kitchenowl-notify";
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

    systemd.timers.kitchenowl-notify = {
      description = "KitchenOwl shopping-list poll timer";
      wantedBy = ["timers.target"];
      timerConfig = {
        OnBootSec = "1m";
        OnUnitActiveSec = cfg.interval;
        Persistent = true;
      };
    };
  };
}

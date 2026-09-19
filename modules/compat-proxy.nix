# compat-proxy + LiteLLM, wired together so any Anthropic- or OpenAI-shaped
# client on the tailnet can use this host's Claude Code subscription.
#
# compat-proxy (pkgs/compat-proxy) only speaks the Anthropic Messages API
# (POST /v1/messages) and has zero inbound auth -- it authenticates
# *outbound* to Anthropic using a credentials file and never checks the
# caller's headers at all. LiteLLM sits in front to translate the OpenAI
# chat/completions shape into that route for clients that need it; its own
# master_key is left unset, so it accepts any bearer token as valid, which is
# the "any API key" behaviour asked for without touching compat-proxy's Rust.
#
# Auth is a `claude setup-token` long-lived (~1y) OAuth token, sops-rendered
# into the nested `claudeAiOauth` shape compat-proxy's reader expects (see
# creds.rs) -- not the ~8h token `claude auth login` produces. That file is
# static and root-owned; there is no refresh cycle left to run, only an
# expiry warning (see compat-proxy-token-expiry below) since the token is
# minted manually and needs re-minting roughly yearly.
#
# Session pings (compat-proxy-session) are a *separate* concept: Anthropic
# buckets usage into a 5h rolling window keyed to the hour of first use, so a
# ping every 5h keeps a window continuously open rather than each request
# possibly straddling two windows. This is a billing/rate-limit affordance,
# unrelated to authentication.
{ self, ... }:
{
  nixos =
    {
      config,
      lib,
      pkgs,
      upkgs,
      ...
    }:
    with lib;
    let
      cfg = config.services.compat-proxy;
      home = "/var/lib/compat-proxy";
      ph = name: config.sops.placeholder.${name};
      oauthTokenKey = "services/compat-proxy/oauth-token";

      # Failure handler is a systemd template: one unit, reused via
      # `onFailure = [ "ntfy-failure@<unit>.service" ]` by any service in this
      # module. `%i` is only expanded by systemd at activation, never inside
      # a Nix-generated `script` (that becomes a static store file) -- so the
      # instance name is threaded through as $UNIT via Environment=, which
      # *does* get specifier-expanded, verified empirically before writing this.
      ntfyFailureService = {
        description = "Report a failed %i to ntfy";
        serviceConfig = {
          Type = "oneshot";
          Environment = "UNIT=%i";
          LoadCredential = "ntfy-token:${cfg.ntfyTokenFile}";
        };
        script = ''
          ${pkgs.curl}/bin/curl -fsS \
            -H "Authorization: Bearer $(cat "$CREDENTIALS_DIRECTORY/ntfy-token")" \
            -H "Title: $UNIT failed on ${config.networking.hostName}" \
            -H "Priority: high" \
            -H "Tags: warning" \
            -d "Check journalctl -u $UNIT" \
            https://ntfy.niko.ink/alerts
        '';
      };
    in
    {
      options.services.compat-proxy = {
        enable = mkEnableOption "compat-proxy + LiteLLM Claude Code OAuth gateway";

        package = mkOption {
          type = types.package;
          default = self.packages.${pkgs.stdenv.hostPlatform.system}.compat-proxy;
          defaultText = literalExpression "self.packages.\${system}.compat-proxy";
        };

        claudeCodePackage = mkOption {
          type = types.package;
          default = upkgs.claude-code;
          defaultText = literalExpression "upkgs.claude-code";
          description = ''
            Provides the `claude` CLI used to ping the 5h usage window (see
            `session.onCalendar`). Defaults to the same `upkgs.claude-code`
            build whose version compat-proxy's package pins into its billing
            fingerprint, so the two never drift apart.
          '';
        };

        port = mkOption {
          type = types.port;
          default = 9099;
          description = "Loopback port compat-proxy listens on (it never binds anything but 127.0.0.1).";
        };

        litellmPort = mkOption {
          type = types.port;
          default = 4000;
          description = "Loopback port LiteLLM listens on.";
        };

        ntfyTokenFile = mkOption {
          type = types.path;
          description = "Path (sops secret) to a file whose first line is an ntfy publish token.";
        };

        token.expiresAt = mkOption {
          type = types.int;
          description = ''
            Unix epoch milliseconds when the `claude setup-token` OAuth token
            (stored as the `services/compat-proxy/oauth-token` sops secret in
            modules/shared-secrets.yaml) expires. `claude setup-token` mints a
            ~1 year token and prints its expiry -- convert that date to epoch
            ms and set it here. Enforced two ways: baked into the rendered
            credentials file so compat-proxy itself refuses an expired token
            (creds.rs), and checked daily by compat-proxy-token-expiry, which
            pages ntfy starting 14 days out since there is no automatic
            refresh -- re-minting is a manual, interactive step.
          '';
        };

        session.onCalendar = mkOption {
          type = types.str;
          default = "07,12,17,22:00:00";
          description = ''
            systemd OnCalendar expression for pinging Anthropic to keep the
            5h usage window continuously open. This is unrelated to
            authentication (that's the long-lived token above) -- it's
            Anthropic's rate-limit accounting: usage is bucketed into a
            rolling 5h window keyed to the hour of first use in the window
            (verified empirically: a ping at 09:06 produced a window reset at
            14:00, not 14:06). Each entry here opens the next window exactly
            where the last one ends, so 07/12/17/22 keeps usage continuously
            windowed 07:00-03:00; 03:00-07:00 is uncovered by design.
          '';
        };
      };

      config = mkIf cfg.enable {
        users.users.compat-proxy = {
          isSystemUser = true;
          group = "compat-proxy";
          home = home;
          createHome = true;
        };
        users.groups.compat-proxy = { };

        sops.secrets.${oauthTokenKey}.sopsFile = ./shared-secrets.yaml;

        # Two renderings of the same token: compat-proxy wants the nested
        # claudeAiOauth JSON shape (creds.rs decides Bearer-vs-x-api-key and
        # which beta headers to send based on that shape existing), while the
        # `claude` CLI used for session pings just wants the bare token via
        # CLAUDE_CODE_OAUTH_TOKEN -- a mechanism widely used for headless CI
        # auth, no interactive login or writable credentials file needed.
        sops.templates."compat-proxy-credentials.json" = {
          content = builtins.toJSON {
            claudeAiOauth = {
              accessToken = ph oauthTokenKey;
              expiresAt = cfg.token.expiresAt;
              scopes = [
                "user:inference"
                "user:profile"
              ];
            };
          };
          owner = "compat-proxy";
        };

        sops.templates."compat-proxy-session.env" = {
          content = "CLAUDE_CODE_OAUTH_TOKEN=${ph oauthTokenKey}\n";
          owner = "compat-proxy";
        };

        systemd.services.compat-proxy = {
          description = "compat-proxy: Anthropic Messages API over Claude Code OAuth";
          after = [ "network-online.target" ];
          wants = [ "network-online.target" ];
          wantedBy = [ "multi-user.target" ];
          onFailure = [ "ntfy-failure@%N.service" ];

          environment = {
            HOME = home;
            COMPAT_PROXY_PORT = toString cfg.port;
            COMPAT_PROXY_CREDENTIALS = config.sops.templates."compat-proxy-credentials.json".path;
          };

          serviceConfig = {
            ExecStart = "${getExe cfg.package}";
            User = "compat-proxy";
            Group = "compat-proxy";
            StateDirectory = "compat-proxy";
            WorkingDirectory = home;
            Restart = "on-failure";
            RestartSec = "10s";
            # A crash loop must actually reach `failed` for OnFailure to fire
            # at all -- otherwise Restart= just retries forever in silence.
            StartLimitIntervalSec = "5min";
            StartLimitBurst = 5;

            NoNewPrivileges = true;
            PrivateTmp = true;
            ProtectSystem = "strict";
            ReadWritePaths = [ home ];
            ProtectKernelTunables = true;
            ProtectKernelModules = true;
            ProtectControlGroups = true;
            RestrictSUIDSGID = true;
            RestrictNamespaces = true;
            LockPersonality = true;
            RestrictAddressFamilies = [
              "AF_INET"
              "AF_INET6"
              "AF_UNIX"
            ];
          };
        };

        services.litellm = {
          enable = true;
          host = "127.0.0.1";
          port = cfg.litellmPort;
          # Wildcard rather than an enumerated list: the model string passes
          # straight through to Anthropic untouched (compat-proxy only
          # inspects it for a thinking-support heuristic), so every model id
          # Anthropic ever ships -- current or future -- works here with no
          # list to keep updated. `anthropic/claude-opus-4-5` in, the same
          # string (`*` substituted) out to compat-proxy, which forwards it
          # to api.anthropic.com as-is.
          settings.model_list = [
            {
              model_name = "anthropic/*";
              litellm_params = {
                model = "anthropic/*";
                api_base = "http://127.0.0.1:${toString cfg.port}";
                # compat-proxy ignores inbound auth entirely; this satisfies
                # LiteLLM's own "a key must be configured" requirement only.
                api_key = "not-needed";
              };
            }
          ];
        };
        systemd.services.litellm.onFailure = [ "ntfy-failure@%N.service" ];

        systemd.services."ntfy-failure@" = ntfyFailureService;

        systemd.services.compat-proxy-session = {
          description = "Ping Anthropic to keep compat-proxy's 5h usage window open";
          onFailure = [ "ntfy-failure@%N.service" ];

          environment.HOME = home;

          serviceConfig = {
            Type = "oneshot";
            User = "compat-proxy";
            Group = "compat-proxy";
            StateDirectory = "compat-proxy";
            WorkingDirectory = home;
            EnvironmentFile = config.sops.templates."compat-proxy-session.env".path;
          };

          script = ''
            set -euo pipefail
            ${cfg.claudeCodePackage}/bin/claude -p "hi" --model haiku >/dev/null

            # Log-only, not a failure: worth having in the journal when
            # diagnosing window alignment, but a drifted window isn't worth
            # paging over.
            reset=$(${pkgs.curl}/bin/curl -fsS "http://127.0.0.1:${toString cfg.port}/v1/usage" \
              | ${pkgs.jq}/bin/jq -r '.five_hour_reset // empty')
            if [ -n "$reset" ]; then
              echo "compat-proxy-session: 5h window resets at $(${pkgs.coreutils}/bin/date -d "@$reset" --iso-8601=seconds)"
            fi

            # Each ping leaves a session transcript behind; prune what this
            # unit itself accumulates so it doesn't grow forever.
            ${pkgs.findutils}/bin/find "${home}/.claude/projects" -name '*.jsonl' -mtime +7 -delete
          '';
        };

        systemd.timers.compat-proxy-session = {
          description = "compat-proxy usage-window session timer";
          wantedBy = [ "timers.target" ];
          timerConfig = {
            OnCalendar = cfg.session.onCalendar;
            Persistent = true;
          };
        };

        systemd.services.compat-proxy-token-expiry = {
          description = "Check compat-proxy's long-lived OAuth token isn't expiring soon";
          onFailure = [ "ntfy-failure@%N.service" ];
          serviceConfig.Type = "oneshot";
          script = ''
            set -euo pipefail
            now_ms=$(( $(${pkgs.coreutils}/bin/date +%s) * 1000 ))
            remaining_days=$(( (${toString cfg.token.expiresAt} - now_ms) / 86400000 ))
            echo "compat-proxy-token-expiry: $remaining_days days remaining"

            if [ "$remaining_days" -lt 14 ]; then
              echo "compat-proxy-token-expiry: token expires in $remaining_days days -- run 'claude setup-token', update the oauth-token secret and services.compat-proxy.token.expiresAt" >&2
              exit 1
            fi
          '';
        };

        systemd.timers.compat-proxy-token-expiry = {
          description = "Daily compat-proxy OAuth token expiry check";
          wantedBy = [ "timers.target" ];
          timerConfig = {
            OnCalendar = "daily";
            Persistent = true;
          };
        };
      };
    };
}

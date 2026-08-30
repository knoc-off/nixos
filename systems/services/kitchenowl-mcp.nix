# MCP server for the KitchenOwl household on this host.
#
# Sits alongside the KitchenOwl container and talks to it over loopback with a
# long-lived API token. Exposes a small curated tool surface: compact reads, and
# writes that are validated against KitchenOwl's own markdown/item rules before
# anything is persisted.
#
# Auth comes in two mutually exclusive shapes, because MCP clients differ:
#
#   - `mcpTokenFile`: a shared bearer token, checked in constant time ahead of
#     the MCP app. Fine for CLI clients that can set a header.
#   - `oauth`: a GitHub-backed OAuth flow, for clients (Claude's web connector)
#     that only speak OAuth and have nowhere to paste a token.
#
# Either way the vhost deliberately skips the `auth-public` snippet -- MCP
# clients cannot follow an interactive redirect to auth.niko.ink. In OAuth mode
# the server runs its own authorization endpoints instead, and `allowedGitHubUsers`
# is what keeps the rest of GitHub out.
{
  self,
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.services.kitchenowl-mcp;
  oauthBaseUrl = if cfg.oauth.baseUrl != null then cfg.oauth.baseUrl else "https://${cfg.domain}";
in
{
  options.services.kitchenowl-mcp = {
    enable = mkEnableOption "KitchenOwl MCP server";

    package = mkOption {
      type = types.package;
      default = self.packages.${pkgs.stdenv.hostPlatform.system}.kitchenowl-mcp;
      defaultText = literalExpression "self.packages.\${system}.kitchenowl-mcp";
      description = "The kitchenowl-mcp package to run.";
    };

    householdId = mkOption {
      type = types.int;
      default = 1;
      description = ''
        KitchenOwl household ("home") id. Pinned here rather than threaded
        through every tool signature, since this server serves one household.
      '';
    };

    apiBase = mkOption {
      type = types.str;
      default = "http://127.0.0.1:3043";
      description = "Base URL of the KitchenOwl backend (no trailing slash). The API lives under /api.";
    };

    host = mkOption {
      type = types.str;
      default = "127.0.0.1";
      description = "Address to bind. Keep on loopback and reverse-proxy to it.";
    };

    port = mkOption {
      type = types.port;
      default = 3044;
      description = "Port to bind.";
    };

    domain = mkOption {
      type = types.nullOr types.str;
      default = null;
      example = "kitchenowl-mcp.niko.ink";
      description = ''
        If set, a Caddy virtual host is created for this domain. The vhost does
        not import `auth-public`: authentication is handled by the server
        itself, either as a bearer token or via the OAuth endpoints it serves
        on this same domain.
      '';
    };

    enableRawGet = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Expose the `kitchenowl_get` tool, a read-only escape hatch onto any
        /api path. Useful, but it widens the read surface to the whole
        household (planner, shopping lists, expenses), not just recipes.
      '';
    };

    styleGuideFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = "Override the recipe style guide returned by `get_style_guide`.";
    };

    apiTokenFile = mkOption {
      type = types.path;
      description = ''
        Path (sops secret) to a file whose contents are a KitchenOwl long-lived
        token. Used to talk to KitchenOwl; never exposed over MCP.
      '';
    };

    mcpTokenFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = ''
        Path (sops secret) to a file whose contents are the bearer token MCP
        clients must present. Must be distinct from `apiTokenFile`: this one is
        handed to clients, and a leak of it should not imply KitchenOwl account
        access. Mutually exclusive with `oauth.enable`.
      '';
    };

    oauth = {
      enable = mkEnableOption "" // {
        description = ''
          Authenticate MCP clients via GitHub OAuth instead of a bearer
          token, for clients that cannot send an Authorization header.

          The server exposes its own OAuth endpoints (discovery, dynamic
          client registration, consent, callback) on `domain` and proxies
          them upstream to a GitHub OAuth app.
        '';
      };

      clientId = mkOption {
        type = types.str;
        default = "";
        example = "Ov23liAbcDefGhiJkLmN";
        description = ''
          Client ID of a GitHub OAuth app whose callback URL is
          `https://<domain>/auth/callback`. This must be an app of its own:
          GitHub allows a single callback per app, and the oauth2-proxy app is
          already using its own.

          Not a secret (it appears in the browser during the OAuth redirect);
          use `clientIdFile` instead to keep it out of the world-readable Nix
          store anyway.
        '';
      };

      clientIdFile = mkOption {
        type = types.nullOr types.path;
        default = null;
        description = "Path (sops secret) holding the client ID, as an alternative to `clientId`.";
      };

      clientSecretFile = mkOption {
        type = types.nullOr types.path;
        default = null;
        description = "Path (sops secret) to the GitHub OAuth app client secret.";
      };

      allowedGitHubUsers = mkOption {
        type = types.listOf types.str;
        default = [ ];
        example = [ "octocat" ];
        description = ''
          GitHub logins permitted to use this server. Checked on every request,
          so revoking someone takes effect immediately rather than when their
          token expires.

          A successful GitHub login only proves the caller has *a* GitHub
          account, so this list -- not the OAuth flow -- is what actually
          restricts access. It must be non-empty.
        '';
      };

      allowedRedirectUris = mkOption {
        type = types.nullOr (types.listOf types.str);
        default = null;
        example = [ "https://claude.ai/api/mcp/auth_callback" ];
        description = ''
          Redirect URI patterns accepted from registering MCP clients. Null
          keeps the built-in default (Anthropic's connector callbacks).

          Do not widen this casually: the upstream library's own default is to
          accept any redirect URI, which would let a malicious client have
          authorization codes delivered to itself.
        '';
      };

      baseUrl = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = ''
          Public https URL the OAuth endpoints are reachable at. Defaults to
          `https://<domain>`, and must match the GitHub app's callback host.
        '';
      };
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.oauth.enable != (cfg.mcpTokenFile != null);
        message = ''
          services.kitchenowl-mcp needs exactly one of `oauth.enable` or
          `mcpTokenFile`. Setting both would leave the static token as a way
          around the GitHub allowlist; setting neither leaves the server
          unauthenticated.
        '';
      }
      {
        assertion = !cfg.oauth.enable || cfg.oauth.allowedGitHubUsers != [ ];
        message = ''
          services.kitchenowl-mcp.oauth.allowedGitHubUsers is empty. GitHub
          authenticates every account on the site, so this would expose the
          household to anyone with a GitHub login.
        '';
      }
      {
        assertion = !cfg.oauth.enable || ((cfg.oauth.clientId != "") != (cfg.oauth.clientIdFile != null));
        message = "services.kitchenowl-mcp.oauth needs exactly one of clientId or clientIdFile.";
      }
      {
        assertion = !cfg.oauth.enable || cfg.oauth.clientSecretFile != null;
        message = "services.kitchenowl-mcp.oauth needs clientSecretFile.";
      }
      {
        assertion = !cfg.oauth.enable || cfg.domain != null || cfg.oauth.baseUrl != null;
        message = ''
          services.kitchenowl-mcp.oauth needs a public URL: set `domain`, or
          `oauth.baseUrl` if the server is reached through some other host.
        '';
      }
    ];

    systemd.services.kitchenowl-mcp = {
      description = "KitchenOwl MCP server";
      wantedBy = [ "multi-user.target" ];
      after = [
        "network-online.target"
        "podman-kitchenowl.service"
      ];
      wants = [ "network-online.target" ];

      environment = {
        KITCHENOWL_API_BASE = cfg.apiBase;
        KITCHENOWL_HOUSEHOLD_ID = toString cfg.householdId;
        KITCHENOWL_MCP_HOST = cfg.host;
        KITCHENOWL_MCP_PORT = toString cfg.port;
        KITCHENOWL_MCP_ENABLE_RAW_GET = boolToString cfg.enableRawGet;
        # Read at exec time from the credentials directory, so no token ever
        # lands in the unit file or the store.
        KITCHENOWL_API_TOKEN_FILE = "%d/api-token";
      }
      // optionalAttrs (cfg.mcpTokenFile != null) {
        KITCHENOWL_MCP_TOKEN_FILE = "%d/mcp-token";
      }
      // optionalAttrs cfg.oauth.enable {
        KITCHENOWL_MCP_OAUTH_BASE_URL = oauthBaseUrl;
        KITCHENOWL_MCP_OAUTH_CLIENT_SECRET_FILE = "%d/oauth-client-secret";
        KITCHENOWL_MCP_OAUTH_ALLOWED_USERS = concatStringsSep "," cfg.oauth.allowedGitHubUsers;
        # Issued-token and client-registration state. Persisted so a restart
        # does not force every client through the consent flow again.
        FASTMCP_HOME = "%S/kitchenowl-mcp/fastmcp";
      }
      // optionalAttrs (cfg.oauth.enable && cfg.oauth.clientIdFile != null) {
        KITCHENOWL_MCP_OAUTH_CLIENT_ID_FILE = "%d/oauth-client-id";
      }
      // optionalAttrs (cfg.oauth.enable && cfg.oauth.clientId != "") {
        KITCHENOWL_MCP_OAUTH_CLIENT_ID = cfg.oauth.clientId;
      }
      // optionalAttrs (cfg.oauth.enable && cfg.oauth.allowedRedirectUris != null) {
        KITCHENOWL_MCP_OAUTH_REDIRECT_URIS = concatStringsSep "," cfg.oauth.allowedRedirectUris;
      }
      // optionalAttrs (cfg.styleGuideFile != null) {
        KITCHENOWL_MCP_STYLE_GUIDE = toString cfg.styleGuideFile;
      };

      serviceConfig = {
        ExecStart = getExe cfg.package;
        Restart = "on-failure";
        RestartSec = 5;

        DynamicUser = true;
        StateDirectory = "kitchenowl-mcp";
        StateDirectoryMode = "0700";
        LoadCredential = [
          "api-token:${toString cfg.apiTokenFile}"
        ]
        ++ optional (cfg.mcpTokenFile != null) "mcp-token:${toString cfg.mcpTokenFile}"
        ++ optionals cfg.oauth.enable (
          [ "oauth-client-secret:${toString cfg.oauth.clientSecretFile}" ]
          ++ optional (cfg.oauth.clientIdFile != null) "oauth-client-id:${toString cfg.oauth.clientIdFile}"
        );

        # Hardening.
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        PrivateDevices = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
        RestrictSUIDSGID = true;
        RestrictNamespaces = true;
        RestrictRealtime = true;
        LockPersonality = true;
        MemoryDenyWriteExecute = true;
        SystemCallArchitectures = "native";
        SystemCallFilter = [
          "@system-service"
          "~@privileged"
          "~@resources"
        ];
        RestrictAddressFamilies = [
          "AF_INET"
          "AF_INET6"
          "AF_UNIX"
        ];
      };
    };

    services.caddy.virtualHosts = mkIf (cfg.domain != null) {
      ${cfg.domain}.extraConfig = ''
        import security-headers
        reverse_proxy ${cfg.host}:${toString cfg.port}
      '';
    };
  };
}

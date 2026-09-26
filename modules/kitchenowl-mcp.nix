# MCP server for the KitchenOwl household on this host.
#
# Sits alongside the KitchenOwl container and talks to it over loopback with a
# long-lived API token. Exposes a small curated tool surface: compact reads, and
# writes that are validated against KitchenOwl's own markdown/item rules before
# anything is persisted.
#
# The MCP server itself authenticates nobody. `proxy` puts mcp-auth-proxy in
# front of it -- a drop-in OAuth 2.1 gateway -- because MCP clients cannot
# follow an interactive redirect to auth.niko.ink, which is why the vhost also
# skips the `auth-public` snippet. The server stays on loopback; the proxy is
# the only thing reachable from Caddy.
{ self, ... }:
{
  nixos =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    with lib;
    let
      cfg = config.services.kitchenowl-mcp;
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
          description = ''
            Address to bind. Keep on loopback: the server does no authentication
            of its own, and relies on `proxy` being the only public entry point.
          '';
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
            If set, a Caddy virtual host is created for this domain, pointing at
            the auth proxy. The vhost does not import `auth-public`: MCP clients
            cannot follow the interactive redirect it issues.
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

        proxy = {
          enable = mkEnableOption "" // {
            description = ''
              Run mcp-auth-proxy in front of the MCP server. It terminates the
              OAuth 2.1 flow MCP clients expect, issues its own tokens, and
              proxies authenticated requests through to `/mcp` unchanged.

              Without this the server is unauthenticated, so only enable
              `domain` alongside it.
            '';
          };

          package = mkOption {
            type = types.package;
            default = self.packages.${pkgs.stdenv.hostPlatform.system}.mcp-auth-proxy;
            defaultText = literalExpression "self.packages.\${system}.mcp-auth-proxy";
            description = "The mcp-auth-proxy package to run.";
          };

          port = mkOption {
            type = types.port;
            default = 3045;
            description = "Port the proxy listens on. Caddy reverse-proxies to this.";
          };

          passwordHashFile = mkOption {
            type = types.nullOr types.path;
            default = null;
            description = ''
              Path (sops secret) to a bcrypt hash of the login password. A hash
              rather than a plaintext password so it never appears in the
              process table; generate one with

                nix run nixpkgs#apacheHttpd -- htpasswd -nbBC 12 "" yourpassword | cut -d: -f2

              Required: with no hash configured every login attempt fails, which
              locks the server rather than opening it, but silently.
            '';
          };
        };
      };

      config = mkIf cfg.enable {
        assertions = [
          {
            assertion = cfg.proxy.enable -> cfg.proxy.passwordHashFile != null;
            message = ''
              services.kitchenowl-mcp.proxy needs passwordHashFile. Without it
              mcp-auth-proxy has no password to compare against and every login
              fails, leaving the server unreachable rather than unprotected.
            '';
          }
          {
            assertion = cfg.proxy.enable -> cfg.domain != null;
            message = ''
              services.kitchenowl-mcp.proxy needs `domain`: the public https URL
              is the issuer and audience of the tokens it signs, not just a
              vhost name.
            '';
          }
          {
            assertion = cfg.domain != null -> cfg.proxy.enable;
            message = ''
              services.kitchenowl-mcp has a `domain` but no `proxy`. The MCP
              server does not authenticate anyone, so this would publish the
              household to the internet.
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
          // optionalAttrs (cfg.styleGuideFile != null) {
            KITCHENOWL_MCP_STYLE_GUIDE = toString cfg.styleGuideFile;
          };

          serviceConfig = {
            ExecStart = getExe cfg.package;
            Restart = "on-failure";
            RestartSec = 5;

            DynamicUser = true;
            LoadCredential = [ "api-token:${toString cfg.apiTokenFile}" ];

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

        # Password hash reaches the proxy as an environment variable rather than
        # a flag, which would put it in the process table for every local user.
        systemd.services.kitchenowl-mcp-proxy = mkIf cfg.proxy.enable {
          description = "OAuth 2.1 gateway for the KitchenOwl MCP server";
          wantedBy = [ "multi-user.target" ];
          after = [ "kitchenowl-mcp.service" ];
          bindsTo = [ "kitchenowl-mcp.service" ];

          environment = {
            # Caddy terminates TLS, so no ACME here -- but the external URL is
            # still the issuer and audience of every token the proxy signs.
            EXTERNAL_URL = "https://${cfg.domain}";
            LISTEN = "127.0.0.1:${toString cfg.proxy.port}";
            NO_AUTO_TLS = "true";
            DATA_PATH = "%S/kitchenowl-mcp-proxy";
            # Caddy is the only thing in front, so its X-Forwarded-* headers are
            # the ones to believe; from anywhere else they are ignored.
            TRUSTED_PROXIES = "127.0.0.1/32";
          };

          serviceConfig = {
            # The hash is exported from the credential rather than passed as
            # --password-hash, which would expose it in the process table.
            # Plain assignment, not `export X=$(...)`: that returns export's
            # status, so a failed read would start the proxy with an empty hash
            # and silently reject every login instead of failing here. Going
            # through a shell also keeps the `$` in a bcrypt hash away from
            # systemd's EnvironmentFile parsing.
            ExecStart = pkgs.writeShellScript "kitchenowl-mcp-proxy-start" ''
              set -euo pipefail
              PASSWORD_HASH=$(cat "$CREDENTIALS_DIRECTORY/password-hash")
              export PASSWORD_HASH
              exec ${getExe cfg.proxy.package} http://${cfg.host}:${toString cfg.port}
            '';
            Restart = "on-failure";
            RestartSec = 5;

            DynamicUser = true;
            # Holds the RSA token-signing key, the session HMAC secret, and the
            # registered-client store. Wiping it invalidates every issued token
            # and forces each client to register again.
            StateDirectory = "kitchenowl-mcp-proxy";
            StateDirectoryMode = "0700";
            LoadCredential = [ "password-hash:${toString cfg.proxy.passwordHashFile}" ];

            # Hardening, matching the MCP server above.
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
          ${cfg.domain} = {
            # The hetzner wildcard cert covers any *.niko.ink name, so a new
            # domain here needs no cert change. Set this to a matching
            # security.acme.certs name if the module is ever used off niko.ink.
            useACMEHost = "niko.ink";
            extraConfig = ''
              import security-headers
              reverse_proxy 127.0.0.1:${toString cfg.proxy.port}
            '';
          };
        };
      };
    };
}

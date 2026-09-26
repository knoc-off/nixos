# MCP server for authoring Anki cards with marki (`marki mcp`).
#
# Runs as the owner of the cards repo so its file writes and git commits land
# as that user, and in the collection's group so it can write the collection
# file that anki-sync-server serves.
#
# The server authenticates nobody and only ever listens on loopback. `proxy`
# puts mcp-auth-proxy in front of it -- the OAuth 2.1 gateway MCP clients
# expect -- and is the only way in. The proxy listens on all interfaces
# because the public vhost lives on another host (hetzner) and reaches it over
# the tailnet; the host's firewall is what limits who can connect (see
# systems/optiplex/services/anki.nix).
{ self, ... }:
{
  nixos =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      inherit (lib)
        getExe
        literalExpression
        mkEnableOption
        mkIf
        mkOption
        types
        ;
      cfg = config.services.marki-mcp;
      hardening = {
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
        SystemCallArchitectures = "native";
        SystemCallFilter = [
          "@system-service"
          "~@privileged"
        ];
        RestrictAddressFamilies = [
          "AF_INET"
          "AF_INET6"
          "AF_UNIX"
        ];
      };
    in
    {
      options.services.marki-mcp = {
        enable = mkEnableOption "marki MCP server";

        package = mkOption {
          type = types.package;
          default = self.packages.${pkgs.stdenv.hostPlatform.system}.marki;
          defaultText = literalExpression "self.packages.\${system}.marki";
          description = "The marki package to run.";
        };

        cardsDir = mkOption {
          type = types.path;
          example = "/srv/flashcards";
          description = "The marki repo (contains `.marki/config.toml`, which names the collection).";
        };

        user = mkOption {
          type = types.str;
          description = "Owner of `cardsDir`; tools write cards and commit as this user.";
        };

        group = mkOption {
          type = types.str;
          default = "anki";
          description = "Group with write access to the Anki collection directory.";
        };

        port = mkOption {
          type = types.port;
          default = 3047;
          description = "Loopback port the MCP server listens on.";
        };

        extraPackages = mkOption {
          type = types.listOf types.package;
          default = [ ];
          description = "Extra tools on PATH (e.g. typst for ```typst blocks).";
        };

        proxy = {
          enable = mkEnableOption "" // {
            description = ''
              Run mcp-auth-proxy in front of the MCP server. It terminates the
              OAuth 2.1 flow MCP clients expect, issues its own tokens, and
              proxies authenticated requests through to `/mcp` unchanged.
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
            default = 3048;
            description = "Port the proxy listens on (all interfaces; firewall it).";
          };

          externalUrl = mkOption {
            type = types.str;
            example = "https://marki-mcp.niko.ink";
            description = ''
              Public https URL clients use. It is the issuer and audience of
              every token the proxy signs, not just a name.
            '';
          };

          trustedProxy = mkOption {
            type = types.str;
            example = "100.64.0.1";
            description = ''
              Address of the reverse proxy in front (the only one whose
              X-Forwarded-* headers are believed).
            '';
          };

          passwordHashFile = mkOption {
            type = types.nullOr types.path;
            default = null;
            description = ''
              Path (sops secret) to a bcrypt hash of the login password. A hash
              rather than a plaintext password so it never appears in the
              process table; generate one with

                nix run nixpkgs#apacheHttpd -- htpasswd -nbBC 12 "" yourpassword | cut -d: -f2

              Required: with no hash configured every login attempt fails.
            '';
          };
        };
      };

      config = mkIf cfg.enable {
        assertions = [
          {
            assertion = cfg.proxy.enable -> cfg.proxy.passwordHashFile != null;
            message = ''
              services.marki-mcp.proxy needs passwordHashFile. Without it
              mcp-auth-proxy has no password to compare against and every login
              fails, leaving the server unreachable rather than unprotected.
            '';
          }
        ];

        systemd.services.marki-mcp = {
          description = "marki MCP server";
          wantedBy = [ "multi-user.target" ];
          after = [
            "network-online.target"
            "anki-sync-server.service"
          ];
          wants = [ "network-online.target" ];
          # git for the post-push commit; systemctl for the config's
          # `[server] stop/start`, which pause anki-sync-server around a push
          # (the host must let cfg.user do that, e.g. via polkit).
          path = [
            pkgs.gitMinimal
            config.systemd.package
          ]
          ++ cfg.extraPackages;
          environment = {
            # Renderer cache (map/typst output) goes to the cache dir.
            XDG_CACHE_HOME = "%C/marki-mcp";
            HOME = "%C/marki-mcp";
            # HOME is the cache dir, so cfg.user's git identity isn't seen;
            # the post-push commits are marki's anyway.
            GIT_AUTHOR_NAME = "marki";
            GIT_AUTHOR_EMAIL = "marki@${config.networking.hostName}";
            GIT_COMMITTER_NAME = "marki";
            GIT_COMMITTER_EMAIL = "marki@${config.networking.hostName}";
          };

          serviceConfig = hardening // {
            # Loopback only; the proxy dials 127.0.0.1, which rmcp's default
            # Host allow-list accepts.
            ExecStart = "${getExe cfg.package} mcp --listen 127.0.0.1:${toString cfg.port}";
            WorkingDirectory = cfg.cardsDir;
            User = cfg.user;
            Group = cfg.group;
            # The collection's -wal/-journal must stay group-writable.
            UMask = "0007";
            CacheDirectory = "marki-mcp";
            Restart = "on-failure";
            RestartSec = 5;
            # Writes only the cards repo, the collection dir, the cache and
            # /tmp (simulation snapshots).
            ReadWritePaths = [
              cfg.cardsDir
              "/var/lib/anki-sync-server"
            ];
          };
        };

        systemd.services.marki-mcp-proxy = mkIf cfg.proxy.enable {
          description = "OAuth 2.1 gateway for the marki MCP server";
          wantedBy = [ "multi-user.target" ];
          after = [ "marki-mcp.service" ];
          bindsTo = [ "marki-mcp.service" ];

          environment = {
            # TLS ends at the reverse proxy in front.
            EXTERNAL_URL = cfg.proxy.externalUrl;
            LISTEN = ":${toString cfg.proxy.port}";
            NO_AUTO_TLS = "true";
            DATA_PATH = "%S/marki-mcp-proxy";
            TRUSTED_PROXIES = "${cfg.proxy.trustedProxy}/32";
          };

          serviceConfig = hardening // {
            # The hash is read from the credential rather than passed as
            # --password-hash, which would expose it in the process table. Plain
            # assignment, not `export X=$(...)`, so a failed read aborts here
            # instead of starting with an empty hash.
            ExecStart = pkgs.writeShellScript "marki-mcp-proxy-start" ''
              set -euo pipefail
              PASSWORD_HASH=$(cat "$CREDENTIALS_DIRECTORY/password-hash")
              export PASSWORD_HASH
              exec ${getExe cfg.proxy.package} http://127.0.0.1:${toString cfg.port}
            '';
            Restart = "on-failure";
            RestartSec = 5;
            DynamicUser = true;
            # Token-signing key, session secret and registered clients. Wiping
            # it invalidates every token and forces clients to register again.
            StateDirectory = "marki-mcp-proxy";
            StateDirectoryMode = "0700";
            LoadCredential = [ "password-hash:${toString cfg.proxy.passwordHashFile}" ];
            MemoryDenyWriteExecute = true;
          };
        };
      };
    };
}

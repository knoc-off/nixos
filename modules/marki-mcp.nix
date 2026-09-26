# MCP server for authoring Anki cards with marki (`marki mcp`).
#
# Runs as the owner of the cards repo so its file writes and git commits land
# as that user, and in the collection's group so it can write the collection
# file that anki-sync-server serves. It authenticates nobody: keep `domain`
# tailnet-only (DNS points at a tailscale IP, the firewall only opens 443 on
# tailscale0), and put mcp-auth-proxy in front before exposing it further.
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
        mkEnableOption
        mkIf
        mkOption
        types
        ;
      cfg = config.services.marki-mcp;
    in
    {
      options.services.marki-mcp = {
        enable = mkEnableOption "marki MCP server";

        package = mkOption {
          type = types.package;
          default = self.packages.${pkgs.stdenv.hostPlatform.system}.marki;
          defaultText = lib.literalExpression "self.packages.\${system}.marki";
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
          description = "Loopback port to listen on.";
        };

        domain = mkOption {
          type = types.nullOr types.str;
          default = null;
          example = "marki.optiplex.tail.niko.ink";
          description = ''
            If set, a Caddy vhost for this name proxies to the server, using
            the security.acme cert of the same name.
          '';
        };

        extraPackages = mkOption {
          type = types.listOf types.package;
          default = [ ];
          description = "Extra tools on PATH (e.g. typst for ```typst blocks).";
        };
      };

      config = mkIf cfg.enable {
        systemd.services.marki-mcp = {
          description = "marki MCP server";
          wantedBy = [ "multi-user.target" ];
          after = [
            "network-online.target"
            "anki-sync-server.service"
          ];
          wants = [ "network-online.target" ];
          # git for the post-push commit.
          path = [ pkgs.gitMinimal ] ++ cfg.extraPackages;
          environment = {
            # Renderer cache (map/typst output) goes to the cache dir.
            XDG_CACHE_HOME = "%C/marki-mcp";
            HOME = "%C/marki-mcp";
          };

          serviceConfig = {
            ExecStart = lib.escapeShellArgs (
              [
                (getExe cfg.package)
                "mcp"
                "--listen"
                "127.0.0.1:${toString cfg.port}"
              ]
              ++ lib.optionals (cfg.domain != null) [
                "--allow-host"
                cfg.domain
              ]
            );
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
            NoNewPrivileges = true;
            ProtectSystem = "strict";
            ProtectHome = true;
            ReadWritePaths = [
              cfg.cardsDir
              "/var/lib/anki-sync-server"
            ];
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
        };

        services.caddy.virtualHosts = mkIf (cfg.domain != null) {
          ${cfg.domain} = {
            useACMEHost = cfg.domain;
            extraConfig = ''
              reverse_proxy 127.0.0.1:${toString cfg.port}
            '';
          };
        };
      };
    };
}

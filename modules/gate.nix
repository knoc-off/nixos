# Gate -- Minecraft reverse proxy (services.gate).
#
# Standalone and generic. Intended to run on a public host (hetzner) as the
# Internet-facing entrypoint, routing per-hostname to Minecraft backends reached
# over Headscale. Exposed as self.nixosModules.gate.
#
# `settings` is the *entire* Gate YAML document, not just its `config:` key.
# Gate's `connect:` block is a sibling of `config:`, and leaving it at the
# upstream default registers this endpoint with Minekube's public Connect
# network -- so callers must be able to reach it to turn it off.
{ ... }: {
  nixos =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.services.gate;
      settingsFormat = pkgs.formats.yaml { };
      configFile = settingsFormat.generate "gate-config.yaml" cfg.settings;
    in
    {
      options.services.gate = {
        enable = lib.mkEnableOption "Gate Minecraft reverse proxy";

        package = lib.mkPackageOption pkgs "gate" { };

        settings = lib.mkOption {
          type = settingsFormat.type;
          default = { };
          description = ''
            Gate configuration, serialised to YAML and passed with `-c`. This is
            the whole document: proxy settings live under `config`, while
            `connect` is a sibling key.

            See https://gate.minekube.com/guide/config/
          '';
          example = lib.literalExpression ''
            {
              config = {
                bind = "0.0.0.0:25565";
                lite = {
                  enabled = true;
                  routes = [
                    {
                      host = ["mc.example.com"];
                      backend = ["10.0.0.2:25565"];
                    }
                  ];
                };
              };
              connect.enabled = false;
            }
          '';
        };
      };

      config = lib.mkIf cfg.enable {
        # Render the effective config without deploying, to diff against intent.
        environment.systemPackages = [
          (pkgs.writeShellScriptBin "gateConfigPrint" ''
            exec ${pkgs.coreutils}/bin/cat ${configFile}
          '')
        ];

        systemd.services.gate = {
          description = "Gate Minecraft reverse proxy";
          after = [ "network-online.target" ];
          wants = [ "network-online.target" ];
          wantedBy = [ "multi-user.target" ];

          serviceConfig = {
            ExecStart = "${lib.getExe cfg.package} -c ${configFile}";
            Restart = "always";
            RestartSec = "5s";

            # Gate reads its config from the store and logs to the journal, so it
            # needs no writable state. Enabling Connect would change that -- it
            # persists a connect.json and would need a StateDirectory.
            DynamicUser = true;
            ProtectSystem = "strict";
            ProtectHome = true;
            PrivateTmp = true;
            PrivateDevices = true;
            ProtectClock = true;
            ProtectControlGroups = true;
            ProtectHostname = true;
            ProtectKernelLogs = true;
            ProtectKernelModules = true;
            ProtectKernelTunables = true;
            ProtectProc = "invisible";
            NoNewPrivileges = true;
            LockPersonality = true;
            RestrictNamespaces = true;
            RestrictRealtime = true;
            RestrictSUIDSGID = true;
            # Binds 25565, so no privileged-port capability is needed.
            CapabilityBoundingSet = [ "" ];
            AmbientCapabilities = [ "" ];
            RestrictAddressFamilies = [
              "AF_INET"
              "AF_INET6"
            ];
            SystemCallArchitectures = "native";
            SystemCallFilter = [
              "@system-service"
              "~@privileged @resources"
            ];
            UMask = "0077";
          };
        };
      };
    };
}

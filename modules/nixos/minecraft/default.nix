{ config, lib, pkgs, inputs, self, ... }:

with lib;

let
  cfg = config.services.minecraft-server-suite;

  # Generate RCON configuration for a server, local-only
  generateRconConfig = serverName: server: {
    "${serverName}" = {
      address = "127.0.0.1:${toString server.serverProperties."rcon.port"}";
      port = server.serverProperties."rcon.port";
      password = server.serverProperties."rcon.password";
      timeout = "10s";
      type = "rcon";
    };
  };

in {

  imports = [
    inputs.nix-minecraft.nixosModules.minecraft-servers
    ./gate-reverse-proxy.nix
  ];

  options.services.minecraft-server-suite = {
    enable = mkEnableOption "Enable Minecraft server suite";

    gate = {  # this might not work, have not tested.
      enable = mkEnableOption "Enable Gate reverse proxy";

      customRoutes = mkOption {
        type = types.listOf (types.submodule {
          options = {
            host = mkOption {
              type = types.str;
              description = "Host domain";
            };
            backend = mkOption {
              type = types.str;
              description = "Backend address";
            };
          };
        });
        default = [];
        description = "Additional Gate proxy routes";
      };

      domain = mkOption {
        type = types.str;
        description = "Base domain for Minecraft servers";
      };
    };

    rcon = {
      enable = mkEnableOption "Enable RCON support";

      package = mkOption {
        type = types.package;
        default = self.packages.${pkgs.system}.rcon-cli;
        description = "RCON client package";
      };
    };
  };

  config = mkIf cfg.enable {
    nixpkgs.overlays = [ inputs.nix-minecraft.overlay ];
    nixpkgs.config.allowUnfree = true;
    # Enable minecraft-servers service
    services.minecraft-servers = {
      eula = true;
      enable = true;
    };

    # Gate reverse proxy configuration
    services.gateService = mkIf cfg.gate.enable {
      enable = true;
      config = {
        lite = {
          enabled = true;
          routes = (mapAttrsToList (serverName: server: {
            host = "${serverName}.${cfg.gate.domain}";
            backend = "localhost:${toString server.serverProperties."server-port"}";
          }) config.services.minecraft-servers.servers) ++ cfg.gate.customRoutes;
        };
      };
    };

    # RCON configuration
    environment.systemPackages = mkIf cfg.rcon.enable [
      (let
        rconConfigs = lib.foldl' (acc: server:
          acc // (generateRconConfig server.name server.value)
        ) {} (mapAttrsToList (name: value: { inherit name value; }) config.services.minecraft-servers.servers);

        rconFile = pkgs.writeTextFile {
          name = "rcon.yaml";
          text = pkgs.lib.generators.toYAML {} rconConfigs;
        };
      in pkgs.writeShellScriptBin "mcrcon" ''
        ${cfg.rcon.package}/bin/gorcon --config ${rconFile} -e "$@"
      '')
    ];

    # i only want the gate services to be outwards facing.
    # Networking configuration
    networking.firewall = {
      allowedUDPPorts = [ 25565 ];
      allowedTCPPorts = [ 25565 ];
    };
  };
}

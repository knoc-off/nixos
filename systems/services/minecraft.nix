# Minecraft server — bricks-building-extended (NeoForge 1.21.1)
#
# Runs on framework13 (dev). The server itself comes from the modpack flake's
# nixosModules.default, which defines services.minecraft-servers.servers.
# "bricks-building-extended" and enables the nix-minecraft service. Here we add
# only the host-side concerns: a sops-provided RCON password, a tailnet-scoped
# firewall, and a local `mcrcon` wrapper.
#
# Exposure model (no third-party): the public entrypoint is Gate running on
# hetzner, which dials this server over Headscale. So the game port is opened
# ONLY on tailscale0 — never on the WAN interface. Public players reach
# hetzner:25565 -> Gate -> <fw13 tailnet IP>:25565.
{
  inputs,
  self,
  config,
  lib,
  pkgs,
  ...
}: let
  serverName = "bricks-building-extended";
  gamePort = 25565;
  rconPort = 25575;
  envFile = config.sops.secrets."services/minecraft/env".path;
  rcon = self.packages.${pkgs.stdenv.hostPlatform.system}.rcon-cli;
in {
  imports = [inputs.minecraft-modpack.nixosModules.default];

  # Inject the RCON password at runtime via the environment file; the Nix store
  # only ever holds the literal "@RCON_PASSWORD@" placeholder, which
  # nix-minecraft substitutes when it copies server.properties into the data
  # dir at service start.
  services.minecraft-servers.environmentFile = envFile;
  services.minecraft-servers.servers.${serverName}.serverProperties."rcon.password" =
    lib.mkForce "@RCON_PASSWORD@";

  # Game + RCON reachable ONLY over the Headscale tailnet, never the WAN.
  # nix-minecraft opens no ports by default, so this is the sole exposure.
  networking.firewall.interfaces."tailscale0" = {
    allowedTCPPorts = [gamePort rconPort];
    allowedUDPPorts = [gamePort];
  };

  # `sudo mcrcon "<command>"` — reads the secret at runtime, talks to the local
  # RCON port. Run from any tailnet host by pointing your own client at
  # <fw13 tailnet IP>:25575 instead.
  environment.systemPackages = [
    (pkgs.writeShellScriptBin "mcrcon" ''
      set -a; . ${envFile}; set +a
      exec ${rcon}/bin/gorcon -a 127.0.0.1:${toString rconPort} -p "$RCON_PASSWORD" "$@"
    '')
  ];
}

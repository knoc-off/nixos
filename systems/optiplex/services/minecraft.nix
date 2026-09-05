# Minecraft server -- inkwell (NeoForge 1.21.1)
#
# Runs on optiplex. The server itself comes from the modpack flake's
# nixosModules.default, which defines services.minecraft-servers.servers.
# "inkwell" and enables the nix-minecraft service. Here we add
# only the host-side concerns: the sops-provided RCON password, the port
# policy, and a local `mcrcon` wrapper.
#
# Exposure model -- Gate is the ONLY way in:
#
#   player -> mc.niko.ink:25565 (A -> hetzner) -> Gate (Lite) -> here
#
# The tailnet is the transport between Gate and this host, not a second player
# entrypoint. The firewall rule below is scoped to hetzner's tailnet address
# rather than to the tailscale0 interface, so no other tailnet peer -- and
# nothing on the LAN or WAN -- can open a session. There is deliberately no
# MagicDNS record pointing at this host either.
#
# Gate runs in Lite mode, which forwards the connection byte-for-byte: player
# authentication, the server list ping and the NeoForge CONFIG-phase mod
# negotiation are all handled end to end by this server. That is why
# online-mode stays true and no proxy-forwarding mod is installed; see
# https://gate.minekube.com/guide/modded-servers.html. Full proxy mode would
# buy real client IPs at the cost of online-mode=false here, which would let
# anyone reaching this port join as any username.
{
  inputs,
  self,
  config,
  lib,
  pkgs,
  ...
}:
let
  serverName = "inkwell";
  gamePort = 25565;
  rconPort = 25575;

  # Gate runs on hetzner. Literal tailnet IP rather than MagicDNS: iptables
  # resolves names once at rule-insertion time, during early boot before
  # tailscale is up. See lib/tailnet.nix.
  gateHost = self.lib.tailnet.hetzner;

  ph = name: config.sops.placeholder.${name};
  envFile = config.sops.templates."minecraft.env".path;
  rcon = self.packages.${pkgs.stdenv.hostPlatform.system}.rcon-cli;
in
{
  imports = [ inputs.minecraft-modpack.nixosModules.default ];

  # nix-minecraft substitutes @RCON_PASSWORD@ in server.properties from this
  # environment file when it copies the file into the data dir at service
  # start, so only the literal placeholder ever reaches the Nix store. The
  # secret itself is a bare scalar in sops; the KEY=VALUE scaffolding lives
  # here and is resolved at activation.
  sops.templates."minecraft.env".content = ''
    RCON_PASSWORD=${ph "services/minecraft/RCON_PASSWORD"}
  '';

  services.minecraft-servers.environmentFile = envFile;

  services.minecraft-servers.servers.${serverName} = {
    serverProperties = {
      # Overrides the modpack's hardcoded "testpass".
      "rcon.password" = lib.mkForce "@RCON_PASSWORD@";

      # MVP: open to anyone who knows the hostname. Coupled to the public DNS
      # record -- if mc.niko.ink is published, turn this back on.
      #
      # The `whitelist` option is deliberately left empty so nix-minecraft does
      # not generate whitelist.json: files it manages are re-copied on every
      # start, which would clobber runtime `/whitelist add`. Leaving it unset
      # keeps the list server-owned and persistent, so this can later be
      # enabled purely over RCON without touching the config.
      white-list = lib.mkForce false;
    };
  };

  # The world lives on the /minecraft btrfs subvolume mounted at /srv/minecraft.
  # nix-minecraft creates ${dataDir}/${serverName} via tmpfiles; if that
  # subvolume ever failed to mount, the directory would be created on the root
  # filesystem instead and the server would silently generate a brand new world
  # while the real one sat unmounted.
  systemd.services."minecraft-server-${serverName}".unitConfig.RequiresMountsFor = "/srv/minecraft";

  # Only Gate may reach the game port. Scoped to a source address rather than
  # to tailscale0, because the interface form would admit every tailnet peer.
  # IPv4 only: Gate dials the v4 literal above, so v6 stays closed.
  #
  # extraCommands runs before the chain's final reject rule, so a plain append
  # is reached (nixos/modules/services/networking/firewall-iptables.nix).
  networking.firewall.extraCommands = ''
    iptables -A nixos-fw -p tcp -s ${gateHost} --dport ${toString gamePort} -j nixos-fw-accept
  '';

  # RCON is reachable from the whole tailnet, unlike the game port -- it is an
  # admin interface, so the trust boundary is "my machines", not "Gate only".
  # server-ip is unset, so it already binds 0.0.0.0; only the firewall gated it.
  #
  # The password is the sole authorisation check, and RCON grants the full
  # server console, so this is as sensitive as tailnet SSH. The protocol is
  # plaintext, which is acceptable only because WireGuard encrypts the hop --
  # this port must never be reachable off the tailnet.
  networking.firewall.interfaces.tailscale0.allowedTCPPorts = [ rconPort ];

  # `sudo mcrcon "<command>"` -- reads the secret at runtime, talks to the
  # local RCON port.
  environment.systemPackages = [
    (pkgs.writeShellScriptBin "mcrcon" ''
      set -a; . ${envFile}; set +a
      exec ${rcon}/bin/gorcon -a 127.0.0.1:${toString rconPort} -p "$RCON_PASSWORD" "$@"
    '')
  ];
}

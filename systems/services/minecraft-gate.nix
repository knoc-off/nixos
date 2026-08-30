# Public Minecraft entrypoint -- Gate in Lite mode.
#
# Gate is the only Internet-facing listener for Minecraft on this host. It
# routes by the hostname in the client's handshake to the real server, which
# lives on optiplex and is reachable only over the Headscale tailnet.
#
#   player -> mc.niko.ink:25565 (A -> oink) -> Gate -> <optiplex tailnet IP>:25565
#
# Lite mode is a byte-forwarder: player authentication, the server list ping
# and the NeoForge handshake are all handled end to end by the backend, so
# `online-mode = true` over there keeps working untouched and Gate holds no
# secrets.
#
# Tailnet members come through here too: headscale.nix deliberately publishes
# no mc.niko.ink record (a split-horizon record pointing at optiplex would be
# rejected by its firewall, which only accepts the game port from Gate), so
# every client resolves the public name and arrives at this listener.
{ self, ... }:
let
  # Backend lives on optiplex. Literal tailnet IP rather than MagicDNS: this
  # host sets services.tailnet.acceptDns = false and so cannot resolve
  # *.tail.niko.ink. See lib/tailnet.nix.
  inherit (self.lib.tailnet) optiplex;

  gamePort = 25565;
in
{
  imports = [ self.nixosModules.gate ];

  services.gate = {
    enable = true;

    settings = {
      config = {
        bind = "0.0.0.0:${toString gamePort}";

        # Modded NeoForge sends a much larger handshake than vanilla and blows
        # through the 30s default while the backend registries sync.
        readTimeout = "60s";

        lite = {
          enabled = true;

          # No `host: '*'` catch-all on purpose: a scanner hitting this host's
          # IP on 25565 sends no matching virtual host, matches no route and
          # gets dropped. Only clients that already know the name get through.
          routes = [
            {
              host = [ "mc.niko.ink" ];
              backend = [ "${optiplex}:${toString gamePort}" ];
              fallback = {
                motd = "§cServer is offline.\n§7Try again later.";
                version = {
                  name = "§cOffline";
                  protocol = -1;
                };
              };
            }
          ];
        };

        # Cheap per-IP connection limiting in front of the backend. CrowdSec
        # handles the durable bans; this just blunts connection floods.
        quota.connections = {
          enabled = true;
          ops = 5;
          burst = 10;
          maxEntries = 1000;
        };
      };

      # Do not register this endpoint with Minekube's public Connect network.
      connect.enabled = false;
    };
  };
}

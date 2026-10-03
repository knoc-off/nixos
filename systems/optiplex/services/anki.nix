# Anki sync for AnkiDroid over the tailnet. marki (CLI and MCP service)
# pushes markdown cards from /srv/flashcards as another sync client of this
# server, with its own collection copy. Caddy
# terminates TLS (DNS-01 via caddy-common, no public reachability
# needed); the sync server itself only listens on loopback.
#
# Its own subdomain rather than optiplex's bare name: that name is now
# shared with compat-proxy/LiteLLM (services/ai.nix) and has no reason to
# be Anki's home just because Anki got here first.
{
  config,
  pkgs,
  self,
  ...
}:
let
  # Literal tailnet IP: iptables resolves names at rule-insertion time,
  # before tailscale is up (see lib/tailnet.nix).
  inherit (self.lib.tailnet) hetzner;
in
{
  imports = [
    self.nixosModules.marki-mcp
    {
      # Card authoring for LLM agents (see modules/marki-mcp.nix). Public at
      # https://marki-mcp.niko.ink: hetzner's Caddy proxies over the tailnet
      # to the OAuth proxy here, which is the only way to the server.
      services.marki-mcp = {
        enable = true;
        cardsDir = "/srv/flashcards";
        user = "tv";
        # The same account AnkiDroid uses: marki is one more device of tv's.
        # /srv/flashcards/.marki/config.toml reads it via
        # MARKI_SYNC_PASSWORD_FILE (see the module).
        syncPasswordFile = config.sops.secrets."services/anki-sync-server/password".path;
        # For ```typst blocks (typst_binary = "typst" in the cards config).
        extraPackages = [ pkgs.typst ];
        proxy = {
          enable = true;
          externalUrl = "https://marki-mcp.niko.ink";
          trustedProxy = hetzner;
          passwordHashFile = config.sops.secrets."services/marki-mcp/password-hash".path;
        };
      };
      sops.secrets."services/marki-mcp/password-hash" = { };

      # Only hetzner's Caddy may reach the proxy. Scoped to its source address
      # rather than tailscale0, which would admit every tailnet peer (same
      # pattern as the Minecraft game port in minecraft.nix).
      networking.firewall.extraCommands = ''
        iptables -A nixos-fw -p tcp -s ${hetzner} --dport ${toString config.services.marki-mcp.proxy.port} -j nixos-fw-accept
      '';
    }
  ];

  services.anki-sync-server = {
    enable = true;
    address = "127.0.0.1";
    port = 27701;
    users = [
      {
        username = "tv";
        passwordFile = config.sops.secrets."services/anki-sync-server/password".path;
      }
    ];
  };

  services.caddy.virtualHosts."anki.optiplex.tail.niko.ink" = {
    useACMEHost = "anki.optiplex.tail.niko.ink";
    extraConfig = ''
      reverse_proxy localhost:27701
    '';
  };

  systemd.tmpfiles.rules = [ "d /srv/flashcards 0755 tv users -" ];
}

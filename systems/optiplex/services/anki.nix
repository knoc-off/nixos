# Anki sync for AnkiDroid over the tailnet; marki pushes markdown cards
# from /srv/flashcards directly into the served collection file. Caddy
# terminates TLS (DNS-01 via caddy-common, no public reachability
# needed); the sync server itself only listens on loopback.
#
# Its own subdomain rather than optiplex's bare name: that name is now
# shared with compat-proxy/LiteLLM (services/ai.nix) and has no reason to
# be Anki's home just because Anki got here first.
{
  config,
  lib,
  self,
  ...
}:
{
  imports = [
    self.nixosModules.marki-mcp
    {
      # Card authoring for LLM agents over the tailnet (see modules/marki-mcp.nix).
      services.marki-mcp = {
        enable = true;
        cardsDir = "/srv/flashcards";
        user = "tv";
        domain = "marki.optiplex.tail.niko.ink";
      };
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

  # marki (as tv, and the marki MCP service) writes the collection file
  # directly, so the upstream DynamicUser isolation is replaced by a static
  # user whose group tv is in. With DynamicUser off, systemd moves the state
  # out of /var/lib/private (0700 root) back to /var/lib/anki-sync-server.
  # Group-writable because SQLite creates its -wal/-journal next to the file.
  users.groups.anki = { };
  users.users.anki-sync-server = {
    isSystemUser = true;
    group = "anki";
  };
  users.users.tv.extraGroups = [ "anki" ];
  systemd.services.anki-sync-server.serviceConfig = {
    DynamicUser = lib.mkForce false;
    User = "anki-sync-server";
    Group = "anki";
    UMask = "0007";
    StateDirectoryMode = "0770";
  };

  services.caddy.virtualHosts."anki.optiplex.tail.niko.ink" = {
    useACMEHost = "anki.optiplex.tail.niko.ink";
    extraConfig = ''
      reverse_proxy localhost:27701
    '';
  };

  systemd.tmpfiles.rules = [
    "d /srv/flashcards 0755 tv users -"
    # One-time fixup of files the DynamicUser era left owned by nobody;
    # idempotent afterwards.
    "Z /var/lib/anki-sync-server 0770 anki-sync-server anki -"
  ];
}

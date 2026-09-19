# Anki sync for AnkiDroid over the tailnet; marki pushes markdown cards
# from /srv/flashcards directly into the served collection file. Caddy
# terminates TLS (DNS-01 via caddy-common, no public reachability
# needed); the sync server itself only listens on loopback.
#
# Its own subdomain rather than optiplex's bare name: that name is now
# shared with compat-proxy/LiteLLM (services/ai.nix) and has no reason to
# be Anki's home just because Anki got here first.
{ config, ... }:
{
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

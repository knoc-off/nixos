# Usenet acquisition stack via nixflix: Prowlarr (indexers) -> Sonarr/Radarr
# -> SABnzbd. nixflix wires the apps together through their REST APIs
# (indexer sync, download client, categories, root folders), so nothing has
# to be clicked through in the UIs. Recyclarr keeps the TRaSH profiles synced.
#
# Downloads and library share the /srv/media subvolume so imports are
# hardlinks/atomic renames instead of copies.
#
# Secrets are { _secret = path; } refs: nixflix reads them as root
# (LoadCredential / ExecStartPre=+), so plain root-owned sops secrets work
# and no sops template is needed.
{
  config,
  inputs,
  lib,
  ...
}:
let
  domain = "optiplex.tail.niko.ink";
  secret = name: { _secret = config.sops.secrets.${name}.path; };
in
{
  imports = [ inputs.nixflix.nixosModules.default ];

  sops.secrets = lib.genAttrs [
    "services/sonarr/api-key"
    "services/sonarr/password"
    "services/radarr/api-key"
    "services/radarr/password"
    "services/prowlarr/api-key"
    "services/prowlarr/password"
    "services/sabnzbd/api-key"
    "services/sabnzbd/nzb-key"
    "services/sabnzbd/password"
    "services/indexers/nzbgeek/api-key"
    "services/indexers/nzbfinder/api-key"
    "services/usenet/frugal/username"
    "services/usenet/frugal/password"
  ] (_: { });

  nixflix = {
    enable = true;
    mediaDir = "/srv/media";
    downloadsDir = "/srv/media/downloads";
    mediaUsers = [ "tv" ];

    # Only for the vhosts nixflix generates; certificates come from
    # caddy-common's lego DNS-01 via the useACMEHost overrides below.
    caddy = {
      enable = true;
      inherit domain;
      tls.enable = true;
    };

    sonarr = {
      enable = true;
      config = {
        apiKey = secret "services/sonarr/api-key";
        hostConfig.password = secret "services/sonarr/password";
      };
    };

    radarr = {
      enable = true;
      config = {
        apiKey = secret "services/radarr/api-key";
        hostConfig.password = secret "services/radarr/password";
      };
    };

    prowlarr = {
      enable = true;
      config = {
        apiKey = secret "services/prowlarr/api-key";
        hostConfig.password = secret "services/prowlarr/password";
        # Prowlarr tests every indexer on add, so a wrong key fails
        # prowlarr-config. `name` must match a Prowlarr schema; anything else
        # uses schemaName = "Generic Newznab" with its own baseUrl.
        indexers = [
          {
            name = "NZBgeek";
            apiKey = secret "services/indexers/nzbgeek/api-key";
          }
          {
            name = "NZBFinder";
            apiKey = secret "services/indexers/nzbfinder/api-key";
          }
        ];
      };
    };

    usenetClients.sabnzbd = {
      enable = true;
      settings = {
        misc = {
          api_key = secret "services/sabnzbd/api-key";
          nzb_key = secret "services/sabnzbd/nzb-key";
          username = "tv";
          password = secret "services/sabnzbd/password";
        };
        # Both use the same Frugal account. The bonus server sits on a
        # different backbone (UsenetFarm), so it fills articles missing from
        # the main one; priority 1 + optional keeps it as a fallback only,
        # which matters because it has a monthly data cap.
        servers =
          let
            frugal = {
              port = 563;
              ssl = true;
              username = secret "services/usenet/frugal/username";
              password = secret "services/usenet/frugal/password";
              # SABnzbd works through the queue one job at a time, so the
              # pre-check (one tiny STAT per article) is bound by round trips,
              # not bandwidth: with 1 request in flight per connection it ran
              # at ~2 articles/s/conn against Frugal. SABnzbd's docs suggest
              # 5-10 for high-latency servers.
              pipelining_requests = 10;
            };
          in
          [
            (
              frugal
              // {
                # Amsterdam: the closest Frugal endpoint to Berlin. Frugal
                # allows up to 100 (billing.frugalusenet.com/page/newsreader);
                # 60 measured ~80 MB/s, so 90 aims at the full gigabit line.
                name = "frugal-eu";
                host = "eunews.frugalusenet.com";
                connections = 90;
                priority = 0;
              }
            )
            (
              frugal
              // {
                # Up to 50 allowed; it only sees articles missing from eunews.
                name = "frugal-bonus";
                host = "bonus.frugalusenet.com";
                connections = 20;
                priority = 1;
                optional = true;
              }
            )
          ];
      };
    };

    recyclarr.enable = true;
  };

  services.caddy.virtualHosts = lib.genAttrs (map (s: "${s}.${domain}") [
    "sonarr"
    "radarr"
    "prowlarr"
    "sabnzbd"
  ]) (name: { useACMEHost = name; });
}

# Headscale control plane + embedded DERP relay. Runs on the public hub
# (oink). Tailscale clients on every node point at https://headscale.niko.ink
# (reverse-proxied by Caddy on :443). MagicDNS serves the niko.ink service
# names to tailnet IPs via extra_records, replacing the old dnsmasq split DNS.
#
# extra_records values are the nodes' Headscale-assigned tailnet IPs. Headscale
# allocates from 100.64.0.0/10 in registration order; after enrolling the nodes
# run `headscale nodes list` and confirm/adjust the IPs below.
{...}: {
  services.headscale = {
    enable = true;
    address = "127.0.0.1";
    port = 8080;

    settings = {
      server_url = "https://headscale.niko.ink";

      # Fully self-hosted relay: enable the embedded DERP and drop the
      # default upstream (Tailscale-operated) DERP map.
      derp = {
        urls = [];
        server = {
          enabled = true;
          region_id = 999;
          region_code = "headscale";
          region_name = "Headscale Embedded DERP";
          stun_listen_addr = "0.0.0.0:3478";
          private_key_path = "/var/lib/headscale/derp_server_private.key";
        };
      };

      dns = {
        magic_dns = true;
        override_local_dns = true;
        base_domain = "tail.niko.ink";
        nameservers.global = ["1.1.1.1" "9.9.9.9"];

        # Split-horizon: tailnet members resolve these service names to the
        # node that serves them; everything else falls through to the global
        # resolvers (so public names like ntfy.niko.ink keep hitting the
        # public IP). A/AAAA only — the sole record types MagicDNS processes.
        extra_records = [
          # home (Home Assistant) is served locally by the Pi.
          {
            name = "home.niko.ink";
            type = "A";
            value = "100.64.0.2";
          }
          # kitchenowl + notes run on the hub; tailnet clients reach the hub
          # over the tailnet so Caddy sees a trusted source and skips OAuth.
          {
            name = "kitchenowl.niko.ink";
            type = "A";
            value = "100.64.0.1";
          }
          {
            name = "notes.niko.ink";
            type = "A";
            value = "100.64.0.1";
          }
        ];
      };
    };
  };
}

# Tailscale data-plane node pointed at the self-hosted Headscale control
# plane. Used by every host on the tailnet. authKeyFile holds a Headscale
# pre-auth key (one per host); the node registers on first start.
#
# --accept-dns=false: this host keeps its own resolver. MagicDNS / the
# niko.ink split-horizon records are for client devices (phones, laptops);
# servers must keep resolving LAN names (e.g. the Zigbee coordinator) and
# their own services locally.
{config, ...}: {
  sops.secrets."services/tailscale/authkey" = {};

  services.tailscale = {
    enable = true;
    openFirewall = true;
    authKeyFile = config.sops.secrets."services/tailscale/authkey".path;
    extraUpFlags = [
      "--login-server=https://headscale.niko.ink"
      "--accept-dns=false"
    ];
  };
}

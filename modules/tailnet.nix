# Tailscale data-plane node pointed at the self-hosted Headscale control
# plane. Used by every host on the tailnet. authKeyFile holds a Headscale
# pre-auth key (one per host, from sops); the node registers declaratively on
# first start.
#
# acceptDns controls --accept-dns. Servers keep it false: they run their own
# resolver and must keep resolving LAN names (e.g. the Zigbee coordinator) and
# their own services locally. Clients (laptops, phones) set it true so MagicDNS
# / the niko.ink split-horizon records resolve to tailnet IPs.
{...}: {
  nixos = {
    config,
    lib,
    ...
  }: let
    cfg = config.services.tailnet;
  in {
    options.services.tailnet = {
      enable = lib.mkEnableOption "Headscale tailnet data-plane node";
      acceptDns = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Whether to accept MagicDNS (--accept-dns). False on servers, true on clients.";
      };
    };

    config = lib.mkIf cfg.enable {
      sops.secrets."services/tailscale/authkey" = {};

      services.tailscale = {
        enable = true;
        openFirewall = true;
        authKeyFile = config.sops.secrets."services/tailscale/authkey".path;
        extraUpFlags =
          ["--login-server=https://headscale.niko.ink"]
          ++ lib.optional (!cfg.acceptDns) "--accept-dns=false";
      };
    };
  };
}



# Shared VPN topology. Per-host overrides set inline.
{self, ...}: {
  imports = [self.nixosModules.services.wireguard-network];

  services.wireguard-network = {
    enable = true;
    domain = "niko.ink";
    subnet = "10.100.0.0/24";
    trustedSubnets = ["10.100.0.0/24" "192.168.178.0/24"];
    hubIp = "10.100.0.1";

    # Services exposed on the home LAN. home.niko.ink runs on the
    # gateway itself (Home Assistant); the others run on the hub and
    # are transparently proxied over WG so LAN clients skip public OAuth.
    lanServices = {
      "home.niko.ink".localBackend = "localhost:8123";
      "kitchenowl.niko.ink" = {};
      "notes.niko.ink" = {};
    };
  };
}

# Shared VPN topology -- imported by all hosts that participate in the
# WireGuard network. Per-host differences (dns upstream, listen address)
# are set inline in each host's imports block.
{self, ...}: {
  imports = [self.nixosModules.services.wireguard-network];

  services.wireguard-network = {
    enable = true;
    domain = "niko.ink";
    subnet = "10.100.0.0/24";
    trustedSubnets = ["10.100.0.0/24" "192.168.178.0/24"];
    hubIp = "10.100.0.1";
    lanOnlySubdomains = ["kitchenowl" "notes" "home"];
  };
}

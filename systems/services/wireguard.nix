# Shared VPN topology. Per-host overrides set inline.
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

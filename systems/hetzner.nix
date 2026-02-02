{
  modulesPath,
  inputs,
  outputs,
  config,
  lib,
  pkgs,
  self,
  ...
}: {
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
    (modulesPath + "/profiles/qemu-guest.nix")

    inputs.sops-nix.nixosModules.sops
    {
      sops = {
        defaultSopsFile = ./secrets/hetzner/default.yaml;
        age.sshKeyPaths = ["/etc/ssh/ssh_host_ed25519_key"];

        secrets = {
          "services/website/env" = {
          };
          "services/kitchenowl/jwt-secret" = {
          };
        };
      };
    }
    inputs.disko.nixosModules.disko
    ./hardware/disks/simple-disk.nix

    ./services/nginx.nix
    ./services/webdav.nix
    ./services/kitchenowl.nix
  ];

  nix.settings.auto-optimise-store = true;
  nix.optimise.automatic = true;

  networking.hostName = "oink";
  networking.firewall = {
    enable = true;
    allowedTCPPorts = [80 443];
  };

  boot.loader.grub = {
    efiSupport = true;
    efiInstallAsRemovable = true;
  };
  services.openssh.enable = true;

  environment.systemPackages = map lib.lowPrio [pkgs.curl pkgs.gitMinimal];

  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJojYXf9Koo8FT/vWB+skUbrgWCkng158wJvHX0zJBXb selby@niko.ink"
  ];

  system.stateVersion = "23.11";
}

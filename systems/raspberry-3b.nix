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
    #./services/octoprint.nix
  ];

  boot = {
    kernelPackages = pkgs.linuxPackages_rpi3;
    loader = {
      grub = {
        efiSupport = true;
        efiInstallAsRemovable = true;
      };
    };
  };

  hardware.enableRedistributableFirmware = true;

  networking = {
    hostName = "rpi3B";
    networkmanager.enable = true;
    wireless.enable = true;
    firewall = {enable = false;};
  };

  swapDevices = [
    {
      device = "/var/lib/swapfile";
      size = 2 * 1024; # 2 GB
    }
  ];

  services.openssh = {
    enable = true;
    settings.PasswordAuthentication = true;
  };

  environment.systemPackages =
    map lib.lowPrio [pkgs.curl pkgs.gitMinimal pkgs.libraspberrypi];

  users.users = {
    root = {
      initialPassword = "password";
      openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJojYXf9Koo8FT/vWB+skUbrgWCkng158wJvHX0zJBXb selby@niko.ink"
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKgy7SAvRGJPBcvt0WA/1oAoR4hDpmJBfRCGqWrygUKG root@nserver"
      ];
    };
  };
}

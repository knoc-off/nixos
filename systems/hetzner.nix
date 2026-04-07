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
          "services/website/env" = {};
          "services/kitchenowl/jwt-secret" = {};
        };
      };
    }
    inputs.disko.nixosModules.disko
    ./hardware/disks/simple-disk.nix

    ./services/caddy.nix
    ./services/crowdsec.nix
    ./services/authelia.nix
    ./services/kitchenowl.nix
    ./services/trilium.nix
  ];

  nix.optimise.automatic = true;
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 30d";
  };

  networking.hostName = "oink";
  networking.firewall = {
    enable = true;
    allowedTCPPorts = [80 443];
    logRefusedConnections = true;
  };

  boot.loader.grub = {
    efiSupport = true;
    efiInstallAsRemovable = true;
  };

  # SSH hardening
  services.openssh = {
    enable = true;
    settings = {
      # Key-only auth -- passwords are brute-forceable on a public server
      PasswordAuthentication = lib.mkForce false;
      KbdInteractiveAuthentication = false;
      X11Forwarding = false;
      PermitRootLogin = "prohibit-password";
      MaxAuthTries = 3;
      LoginGraceTime = 20;
      ClientAliveCountMax = 3;
      ClientAliveInterval = 60;
    };
    # Only ed25519 -- RSA/ECDSA host keys are unnecessary attack surface
    hostKeys = [
      {
        path = "/etc/ssh/ssh_host_ed25519_key";
        type = "ed25519";
      }
    ];
  };


  # Kernel and network hardening for a public-facing host
  boot.kernel.sysctl = {
    "net.ipv4.tcp_syncookies" = 1;
    "net.ipv4.conf.all.rp_filter" = 1;
    "net.ipv4.conf.default.rp_filter" = 1;
    "net.ipv4.conf.all.accept_redirects" = 0;
    "net.ipv4.conf.default.accept_redirects" = 0;
    "net.ipv6.conf.all.accept_redirects" = 0;
    "net.ipv6.conf.default.accept_redirects" = 0;
    "net.ipv4.conf.all.send_redirects" = 0;
    "net.ipv4.conf.default.send_redirects" = 0;
    "net.ipv4.conf.all.accept_source_route" = 0;
    "net.ipv4.conf.default.accept_source_route" = 0;
    "net.ipv6.conf.all.accept_source_route" = 0;
    "net.ipv6.conf.default.accept_source_route" = 0;
    "net.ipv4.conf.all.log_martians" = 1;
    "net.ipv4.conf.default.log_martians" = 1;
    "net.ipv4.icmp_echo_ignore_broadcasts" = 1;
    "net.ipv4.icmp_ignore_bogus_error_responses" = 1;
    "kernel.kptr_restrict" = 2;
    "kernel.dmesg_restrict" = 1;
    "kernel.unprivileged_bpf_disabled" = 1;
    "kernel.perf_event_paranoid" = 3;
    "kernel.yama.ptrace_scope" = 1;
    "net.core.bpf_jit_harden" = 2;
  };

  # Non-root admin -- prefer ssh knoff@ over root for audit trail
  users.users.knoff = {
    isNormalUser = true;
    extraGroups = ["wheel"];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJojYXf9Koo8FT/vWB+skUbrgWCkng158wJvHX0zJBXb selby@niko.ink"
    ];
  };

  security.sudo = {
    enable = true;
    wheelNeedsPassword = true;
    execWheelOnly = true;
  };

  # Root key retained for emergency recovery
  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJojYXf9Koo8FT/vWB+skUbrgWCkng158wJvHX0zJBXb selby@niko.ink"
  ];

  environment.systemPackages = map lib.lowPrio [pkgs.curl pkgs.gitMinimal];

  system.stateVersion = "23.11";
}

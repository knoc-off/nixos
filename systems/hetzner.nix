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
          "wireguard/private-key" = {};
          "cert-sync/ssh-key" = {
            owner = "root";
            mode = "0400";
          };
        };
      };
    }
    inputs.disko.nixosModules.disko
    ./hardware/disks/simple-disk.nix

    ./services/caddy.nix
    ./services/crowdsec.nix
    ./services/oauth2-proxy.nix
    ./services/kitchenowl.nix
    ./services/trilium.nix

    ./services/wireguard.nix
    {
      services.wireguard-network.dns = {
        enable = true;
        localOnly = true;
        listenAddress = "10.100.0.1";
      };
    }

    self.nixosModules.services.cert-sync
    # Ship ACME-issued certs to the Pi over WireGuard whenever Caddy
    # renews them. The Pi's local Caddy terminates TLS for home-LAN
    # clients (home.niko.ink directly to HA, kitchenowl/notes via
    # transparent reverse-proxy back through WG to here). The cert
    # list is derived from lanServices so adding a new LAN-accelerated
    # service is a single-line change in wireguard.nix.
    (
      {
        config,
        lib,
        ...
      }: let
        hubCertDir = "/var/lib/caddy/.local/share/caddy/certificates/acme-v02.api.letsencrypt.org-directory";
        mkCertEntry = host: _svc: {
          name = host;
          certFile = "${hubCertDir}/${host}/${host}.crt";
          keyFile = "${hubCertDir}/${host}/${host}.key";
        };
      in {
        services.cert-sync = {
          enable = true;
          destination = {
            host = "10.100.0.2";
            sshKeyFile = config.sops.secrets."cert-sync/ssh-key".path;
            reloadCommand = "reload-caddy";
          };
          certs = lib.mapAttrsToList mkCertEntry config.services.wireguard-network.lanServices;
        };
      }
    )
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
    allowedUDPPorts = [51820];
    logRefusedConnections = true;
  };

  networking.wireguard.interfaces.wg0 = {
    ips = ["10.100.0.1/24"];
    listenPort = 51820;
    privateKeyFile = config.sops.secrets."wireguard/private-key".path;
    peers = [
      {
        # Pi -- gateway for home LAN
        publicKey = "7tiH8n6rpPN6U2+xJ58Fd9lhkVeS+jduVPA1Uq7IzR0=";
        allowedIPs = ["10.100.0.2/32" "192.168.178.0/24"];
      }
      {
        # Android phone
        publicKey = "E3rALFimpj/yG1JrxemcfYEMwp5neGd7c5EDMoWXS1Q=";
        allowedIPs = ["10.100.0.3/32"];
      }
      {
        # Framework 13 laptop
        publicKey = "Ad+7eq4h0eIrGyFTsziEU+mB5q0/cwat2gW6iVOEtzc=";
        allowedIPs = ["10.100.0.4/32"];
      }
    ];
  };

  services.caddy.virtualHosts."home.niko.ink".extraConfig = ''
    import security-headers
    import lan-only
    reverse_proxy 10.100.0.2:8123
  '';

  # Cap journal size so it doesn't eat disk over time
  services.journald.extraConfig = "SystemMaxUse=500M";

  boot.loader.grub = {
    efiSupport = true;
    efiInstallAsRemovable = true;
  };

  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = lib.mkForce false;
      KbdInteractiveAuthentication = false;
      X11Forwarding = false;
      PermitRootLogin = "prohibit-password";
      MaxAuthTries = 3;
      LoginGraceTime = 20;
      ClientAliveCountMax = 3;
      ClientAliveInterval = 60;
    };
    # ed25519 only -- drop RSA/ECDSA attack surface
    hostKeys = [
      {
        path = "/etc/ssh/ssh_host_ed25519_key";
        type = "ed25519";
      }
    ];
  };


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

  # non-root admin for audit trail
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

  # emergency recovery
  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJojYXf9Koo8FT/vWB+skUbrgWCkng158wJvHX0zJBXb selby@niko.ink"
  ];

  environment.systemPackages = map lib.lowPrio [pkgs.curl pkgs.gitMinimal];

  system.stateVersion = "23.11";
}

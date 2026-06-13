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
          "services/ntfy/env" = {};
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
    ./services/ntfy.nix

    ./services/headscale.nix
    ./services/tailscale.nix

    self.nixosModules.markid
  ];

  # ─────────────────────────────────────────────────────────────────────
  # markid — disabled on this host; runs locally on the Framework 13
  # via the home-manager module. Left in imports for the module to be
  # available if re-enabled later.
  # ─────────────────────────────────────────────────────────────────────
  services.markid.enable = false;

  nix.optimise.automatic = true;
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 30d";
  };
  nix.settings.experimental-features = ["nix-command" "flakes"];

  networking.hostName = "oink";
  networking.firewall = {
    enable = true;
    allowedTCPPorts = [80 443];
    # UDP 3478: STUN for the embedded Headscale DERP relay.
    allowedUDPPorts = [3478];
    logRefusedConnections = true;
  };

  services.caddy.virtualHosts."headscale.niko.ink".extraConfig = ''
    import security-headers
    reverse_proxy localhost:8085
  '';

  services.caddy.virtualHosts."ntfy.niko.ink".extraConfig = ''
    import security-headers
    reverse_proxy localhost:2586
  '';

  # Cap journal size so it doesn't eat disk over time
  services.journald.extraConfig = "SystemMaxUse=500M";

  zramSwap = {
    enable = true;
    memoryPercent = 50;
    algorithm = "zstd";
  };

  systemd.coredump.settings.Coredump.settings = ''
    Storage=none
    ProcessSizeMax=0
  '';
  systemd.tmpfiles.rules = [
    "e /var/lib/systemd/coredump - - - 1d"
  ];

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

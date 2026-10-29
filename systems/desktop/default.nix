{
  lib,
  inputs,
  pkgs,
  self,
  config,
  ...
}:
let
  user = "knoff";
in
{
  imports = [
    self.nixosModules.tailnet
    {
      services.tailnet = {
        enable = true;
        acceptDns = true;
      };
    }

    self.nixosModules.nix-cache
    { services.nixCache.leaf.enable = true; }

    self.nixosModules.users.knoff
    self.nixosModules.nix
    self.nixosModules.nh
    self.nixosModules.pipewire
    self.nixosModules.misc
    self.nixosModules.console
    self.nixosModules.fish
    self.nixosModules.bluetooth

    self.nixosModules.btrfs-luks
    {
      disks.btrfsLuks = {
        enable = true;
        device = "/dev/nvme0n1";
        encryption = true;
        # Room for lanzaboote UKIs (~100 MB each) if Secure Boot comes later.
        espSize = "2G";
        swapSize = "16G";
      };
    }

    self.nixosModules.boot
    {
      boot.custom = {
        enable = true;
        type = "systemd-boot";
        efiSupport = true;
      };
    }

    # Ryzen 9 3900X (Zen 2) + RX 6600 XT (RDNA2, gfx1032).
    inputs.hardware.nixosModules.common-cpu-amd
    inputs.hardware.nixosModules.common-cpu-amd-pstate
    inputs.hardware.nixosModules.common-gpu-amd
    inputs.hardware.nixosModules.common-pc
    inputs.hardware.nixosModules.common-pc-ssd
    {
      # No nixos-generate-config scan exists for this box; these cover a
      # typical AM4 board booting from NVMe with a USB keyboard at the LUKS prompt.
      boot.initrd.availableKernelModules = [
        "nvme"
        "xhci_pci"
        "ahci"
        "usbhid"
        "usb_storage"
        "sd_mod"
      ];
      boot.kernelModules = [ "kvm-amd" ];
      hardware.enableRedistributableFirmware = true;

      # ROCm does not officially support gfx1032; it runs as gfx1030 instead.
      hardware.amdgpu.opencl.enable = true;
      environment.variables.HSA_OVERRIDE_GFX_VERSION = "10.3.0";
      environment.systemPackages = with pkgs; [
        clinfo
        rocmPackages.rocminfo
        nvtopPackages.amd
      ];
    }

    self.nixosModules.hyprland
    self.nixosModules.noctalia
    {
      # No eDP-1 here, so the default auto-center-up would go negative.
      home-manager.users.${user}.hyprland.monitorPosition = "auto";
      services.greetd = {
        enable = true;
        settings.default_session = {
          command = "${pkgs.tuigreet}/bin/tuigreet --time --remember --cmd 'uwsm start hyprland-uwsm.desktop'";
          user = "greeter";
        };
      };
    }

    {
      programs = {
        steam.enable = true;
        gamemode.enable = true;
      };
      hardware.steam-hardware.enable = true;
      services.pipewire.alsa.support32Bit = true;
    }

    self.nixosModules.sops
    {
      sops = {
        defaultSopsFile = ./secrets.yaml;
        secrets = {
          "shell_environment/OPENROUTER_API_KEY".owner = user;
          "shell_environment/RHIZOME_TOKEN" = {
            owner = user;
            sopsFile = ../../modules/shared-secrets.yaml;
          };
          "firefox/kagi-token" = {
            owner = user;
            sopsFile = ../../modules/shared-secrets.yaml;
          };
        };
      };
    }
  ];

  programs = {
    virt-manager.enable = true;
    direnv = {
      enable = true;
      silent = true;
    };
    nix-ld = {
      enable = true;
      libraries = with pkgs; [
        libxcursor
        libxrandr
        libx11
        libGL
        stdenv.cc.cc
        SDL2
        SDL2_image
        libz
      ];
    };
  };

  virtualisation.libvirtd = {
    enable = true;
    qemu.swtpm.enable = true;
  };

  services = {
    gvfs.enable = true;
    udisks2.enable = true;
    openssh.settings = {
      # misc.nix defaults to "no"; nixos-rebuild --target-host root@desktop needs keys.
      PermitRootLogin = "prohibit-password";
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
    };
    # Not wanted on a desktop with no printer; misc.nix turns it on by default.
    printing.enable = false;
  };

  hardware.uinput.enable = true;

  fonts = {
    packages = with pkgs; [
      noto-fonts
      noto-fonts-cjk-sans
      noto-fonts-color-emoji
      liberation_ttf
      nerd-fonts.fira-code
    ];
    fontconfig.defaultFonts.monospace = [ "FiraCode Nerd Font Mono" ];
  };

  boot = {
    binfmt.emulatedSystems = [ "aarch64-linux" ];
    kernel.sysctl = {
      # Bumped for rust-analyzer and other file watchers.
      "fs.inotify.max_user_watches" = 524288;
      "fs.inotify.max_user_instances" = 1024;
    };
  };

  zramSwap = {
    enable = true;
    algorithm = "zstd";
    memoryPercent = 50;
    priority = 100;
  };

  users.users.${user} = {
    shell = pkgs.fish;
    isNormalUser = lib.mkDefault true;
    extraGroups = [
      "wheel"
      "audio"
      "video"
      "render"
      "dialout"
      "uinput"
      "input"
      "gamemode"
      "libvirtd"
    ]
    ++ lib.optional config.networking.networkmanager.enable "networkmanager";
    initialPassword = "password";
    openssh.authorizedKeys.keys = [ self.lib.ssh.user.framework13 ];
  };

  users.users.root.openssh.authorizedKeys.keys = [ self.lib.ssh.user.framework13 ];

  system.stateVersion = "26.05";
}

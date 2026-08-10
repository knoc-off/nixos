{
  inputs,
  config,
  hostname,
  pkgs,
  self,
  ...
}:
let
  user = "tv";
in
{
  imports = [
    ./services/kdeconnect.nix
    ./services/minecraft.nix
    ./services/minecraft-snapshots.nix

    inputs.determinate.nixosModules.default

    inputs.sops-nix.nixosModules.sops
    {
      sops = {
        defaultSopsFile = ./secrets/${hostname}/default.yaml;
        age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];

        secrets = {
          # ntfy token with publish rights, used by wohnungsfinder below.
          "services/ntfy/publish-token" = { };
          # Assembled into an env file by services/minecraft.nix.
          "services/minecraft/RCON_PASSWORD" = { };
        };
      };
    }

    self.nixosModules.tailnet
    {
      services.tailnet = {
        enable = true;
        acceptDns = true;
      };
    }

    self.nixosModules.wohnungsfinder
    {
      # inberlinwohnen.de new-listing watcher -> ntfy.niko.ink.
      services.wohnungsfinder = {
        enable = true;
        ntfy = {
          topic = "wohnungen";
          tokenFile = config.sops.secrets."services/ntfy/publish-token".path;
        };
      };
    }

    self.nixosModules.btrfs-luks
    {
      disks.btrfsLuks = {
        enable = true;
        device = "/dev/nvme0n1";
        # Lanzaboote UKIs bundle kernel + initrd (~100 MB each), so 8
        # generations plus systemd-boot does not fit the 512M module default.
        espSize = "2G";
        swapSize = "8G";
        encryption = true;
        # Enrolled against the pcrlock policy with systemd-cryptenroll; slots 0
        # and 1 remain as passphrase recovery.
        tpm2Unlock = true;
        # Jellyfin library and the Minecraft world get their own subvolumes so
        # they snapshot independently of the rootfs and survive root rollbacks.
        extraSubvolumes = {
          "/media".mountpoint = "/srv/media";
          "/minecraft".mountpoint = "/srv/minecraft";
        };
      };
    }

    self.nixosModules.boot
    {
      # Staged Secure Boot / measured boot rollout on this OptiPlex 7080:
      #
      #  1. Install with nixos-anywhere; LUKS opens from the passphrase passed
      #     via --disk-encryption-keys. That slot stays forever as recovery.
      #  2. BIOS -> Secure Boot -> Expert Key Management -> Delete All Keys, so
      #     the firmware is in Setup Mode (`bootctl status` -> "setup").
      #  3. type = "lanzaboote" plus autoGenerateKeys/autoEnrollKeys below; two
      #     reboots later `bootctl status` reports "enabled (user)".
      #  4. boot.lanzaboote.measuredBoot = { enable = true; pcrs = [ 0 4 7 ]; };
      #     Preflight with `systemd-pcrlock is-supported`.
      #  5. systemd-cryptenroll --tpm2-device=auto \
      #       --tpm2-pcrlock=/var/lib/systemd/pcrlock.json /dev/nvme0n1p2
      #     then set disks.btrfsLuks.tpm2Unlock = true above.
      #
      # pcrlock rather than raw --tpm2-pcrs: lanzaboote regenerates and re-signs
      # the policy on every rebuild, so kernel updates do not lock you out, and
      # PCR 4 covers the whole post-firmware chain via the lanzaboote stub.
      boot.custom = {
        enable = true;
        type = "lanzaboote";
        efiSupport = true;
        # Hard ceiling imposed by systemd-pcrlock (systemd/systemd#41526).
        configurationLimit = 8;
      };

      # The BIOS "Delete All Keys" step left this board in Audit Mode
      # (SetupMode=1, AuditMode=1) rather than plain Setup Mode. systemd-boot
      # accepts both for enrollment, so this works as-is -- but note that
      # enrolling a PK from Audit Mode transitions to Deployed Mode, which
      # cannot be left from the OS. Redoing enrollment means another trip to
      # the BIOS to wipe keys.
      boot.lanzaboote = {
        autoGenerateKeys.enable = true;
        autoEnrollKeys = {
          enable = true;
          # sbctl only stages PK/KEK/db.auth onto the ESP; systemd-boot is what
          # actually writes them to firmware on the following boot. The reboot
          # is part of the mechanism, not a convenience.
          autoReboot = true;
        };

        # PCR 0 is firmware code, 4 the boot loader plus UKI, 7 the Secure Boot
        # policy. 1, 2 and 3 cover firmware configuration and option ROMs and
        # are documented as flaky, so they stay out. Consequence of including
        # 0: a BIOS update invalidates the policy and drops to the passphrase
        # prompt until Phase 5's cryptenroll is re-run. That is a fallback, not
        # a lockout -- LUKS slot 0 is never touched by any of this.
        measuredBoot = {
          enable = true;
          pcrs = [
            0
            4
            7
          ];
        };
      };
    }

    inputs.hardware.nixosModules.common-cpu-intel
    inputs.hardware.nixosModules.common-pc
    inputs.hardware.nixosModules.common-pc-ssd
    {
      # Inlined from nixos-hardware common/cpu/intel/comet-lake: that path has
      # no flake attr, and common-gpu-intel-comet-lake is deprecated
      # (nixos-hardware#992). The i5-10500 is Comet Lake, UHD 630 is Gen9.5.
      #
      # enable_guc=2 loads GuC + HuC. HuC is what gives Jellyfin low-power
      # fixed-function encode.
      boot.kernelParams = [ "i915.enable_guc=2" ];

      hardware.intelgpu = {
        # Gen8-11. The default (intel-compute-runtime) targets Gen12+ and does
        # not support Gen9.5, so OpenCL was silently broken.
        computeRuntime = "legacy";
        # iHD only. The null default installs i965 alongside it, leaving VA-API
        # driver selection ambiguous.
        vaapiDriver = "intel-media-driver";
        # mediaRuntime stays at the vpl-gpu-rt default. It is Gen12+ only and so
        # unused here, but the Gen9.5-correct alternative (intel-media-sdk) is
        # EOL with local privesc CVEs and would need permittedInsecurePackages.
        # Jellyfin uses the VA-API path via intel-media-driver regardless.
      };
    }

    self.nixosModules.pipewire
    {
      # ACP ranks the analog jack above HDMI (prio 6500+ vs 5900), so
      # find-best-profile picks the headphone jack by default even though the
      # TV is the only speaker. Pinning the name here makes selection
      # deterministic across the TV being off/on-another-input at boot, since
      # find-preferred-profile matches on name only and ignores availability.
      services.pipewire.wireplumber.extraConfig."99-tv-hdmi"."device.profile.priority.rules" = [
        {
          matches = [ { "device.name" = "alsa_card.pci-0000_00_1f.3"; } ];
          actions.update-props.priorities = [
            "output:hdmi-stereo+input:analog-stereo"
            "output:hdmi-stereo"
          ];
        }
      ];
    }
    self.nixosModules.users.tv
    self.nixosModules.nix

    {
      services.udisks2.enable = true;
      services.gvfs.enable = true;
      services.devmon.enable = true;
    }

    {
      # Not pulling in self.nixosModules.misc for this: it also flips on
      # printing/avahi/networkmanager/fwupd (all mkDefault, but all unwanted
      # on a TV box). ghostty.nix hardcodes FiraCode Nerd Font Mono and
      # nothing here installed it, so the terminal silently fell back and
      # every nerd-font glyph (starship, icons) rendered as tofu.
      programs.dconf.enable = true;

      fonts = {
        enableDefaultPackages = true;
        packages = with pkgs; [
          noto-fonts
          noto-fonts-cjk-sans
          noto-fonts-color-emoji
          liberation_ttf
          nerd-fonts.fira-code
        ];
        fontconfig.defaultFonts.monospace = [ "FiraCode Nerd Font Mono" ];
      };
    }

    {
      security.sudo.extraRules = [
        {
          users = [ "tv" ];
          commands = [
            {
              command = "ALL";
              options = [
                "NOPASSWD"
                "SETENV"
              ];
            }
          ];
        }
      ];
    }

    {
      # services.sabnzbd = {
      #   enable = true;
      # };

      # need to add a UI, to the user.
      services.jellyfin = {
        enable = true;
        # The firewall is enabled below, so the LAN ports (8096/8920 TCP,
        # 1900/7359 UDP discovery) have to be opened explicitly or streaming to
        # anything other than this box's own display breaks.
        openFirewall = true;
      };

      # Runs as jellyfin:jellyfin with no supplementary groups, so it cannot
      # open /dev/dri/renderD128 (root:render 0660). Without this, hardware
      # transcoding fails silently and every stream is transcoded on the CPU.
      users.users.jellyfin.extraGroups = [
        "render"
        "video"
      ];
    }

    {
      # Idle policy (screen off, no lock/suspend) lives in the tv-away module.
      home-manager.users.${user} = {
        systemd.user.services.sway-audio-idle-inhibit = {
          Unit = {
            Description = "Inhibit idle when audio is playing";
            After = [ "graphical-session.target" ];
            PartOf = [ "graphical-session.target" ];
          };
          Service = {
            ExecStart = "${pkgs.sway-audio-idle-inhibit}/bin/sway-audio-idle-inhibit";
            Restart = "on-failure";
            RestartSec = 5;
          };
          Install.WantedBy = [ "graphical-session.target" ];
        };
      };
    }

    self.nixosModules.hyprland
    self.nixosModules.noctalia
    {
      # extraPackages is owned by hardware.intelgpu above; listing drivers here
      # too just duplicates them and re-adds i965.
      hardware.graphics = {
        enable = true;
        enable32Bit = true;
      };

      services = {
        xserver.displayManager.startx.enable = false;
        getty.autologinUser = user;
        greetd = {
          enable = true;
          settings = {
            default_session = {
              command = "uwsm start hyprland-uwsm.desktop";
              inherit user;
            };
          };
        };
        seatd = {
          enable = true;
          inherit user;
        };
      };

      users.users.${user} = {
        isNormalUser = true;
        extraGroups = [
          "wheel"
          "render"
          "seat"
          "video"
          "audio"
          "input"
          "networkmanager"
          "dialout"
          "plugdev"
        ];
      };

      environment.systemPackages = with pkgs; [
        libdrm
        mesa-demos
        vulkan-tools

        wl-clipboard
        xdg-utils
        dwl
        firefox
        mpv

        bluetuith
        bluez-tools
        bluez-alsa
        wireshark

        libcec

        spotify
        sway-audio-idle-inhibit
      ];
    }

    {
      hardware.steam-hardware.enable = true;

      services.pipewire.alsa.support32Bit = true;
    }
  ];

  services.dbus.enable = true;

  hardware = {
    uinput.enable = true;
    enableRedistributableFirmware = true;
  };

  nix.settings.auto-optimise-store = true;

  # Minecraft's game port is not listed here: services/minecraft.nix opens it
  # via extraCommands scoped to Gate's source address, since a port range or
  # interface rule would admit the whole tailnet.
  networking.firewall = {
    enable = true;
    allowedTCPPortRanges = [
      {
        from = 1714;
        to = 1764;
      }
    ];
    allowedUDPPortRanges = [
      {
        from = 1714;
        to = 1764;
      }
    ];
  };

  # No i915 kernelParams/kernelModules needed here: hardware.intelgpu puts i915
  # in the initrd (loadInInitrd defaults true) and sets enable_guc above.
  # HDMI-CEC is not achievable on this box -- the Intel iGPU exposes no CEC
  # adapter, so libcec needs a USB-CEC dongle (e.g. Pulse-Eight).

  services.openssh.enable = true;

  time.timeZone = "Europe/Berlin";

  environment.systemPackages = [
    pkgs.curl
    pkgs.gitMinimal
    self.packages.${pkgs.stdenv.hostPlatform.system}.session-env
    # inputs.nixgl.packages.x86_64-linux.nixGLIntel
  ];

  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJojYXf9Koo8FT/vWB+skUbrgWCkng158wJvHX0zJBXb selby@niko.ink"
  ];

  system.stateVersion = "26.05";
}

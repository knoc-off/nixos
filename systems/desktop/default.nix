{
  lib,
  inputs,
  pkgs,
  upkgs,
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

    {
      home-manager.users.${user} = {
        # Unstable: Discord refuses to launch on versions it considers stale.
        home.packages = [ upkgs.discord ];
        # knoff.nix's autoload entries are keyed to Framework 13 device names;
        # these are the desktop's onboard codec (front-panel mic + headphones).
        services.easyeffects.autoload = {
          input."alsa_input.pci-0000_2a_00.4.analog-stereo:Front Microphone" = {
            preset = "mic-voice";
            description = "Starship/Matisse HD Audio Controller Analog Stereo";
          };
          output."alsa_output.pci-0000_2a_00.4.analog-stereo:Headphones" = {
            preset = "passthrough";
            description = "Starship/Matisse HD Audio Controller Analog Stereo";
          };
        };
      };

      # The ALC892 defaults Front Mic Boost to +20 dB, which clips speech at
      # 0 dBFS. WirePlumber only manages the Capture mixer, not the boost
      # switch, so set it once per boot; mic-voice is tuned for +10 dB.
      systemd.services.mic-boost = {
        wantedBy = [ "sound.target" ];
        after = [ "sound.target" ];
        serviceConfig = {
          Type = "oneshot";
          ExecStart = "${pkgs.alsa-utils}/bin/amixer -c Generic sset 'Front Mic Boost' 1";
        };
      };
    }

    # Push-to-talk dictation. Pinned HM 26.05 has no services.voxtype module,
    # so the daemon unit is hand-rolled. Parakeet runs on CPU via ONNX: the
    # RX 6600 XT (RDNA2) is too old for voxtype's MIGraphX path.
    (
      let
        # wtype 0.4 (nixpkgs) types literal text on keycode 1 (Esc) and the
        # number row, so keycode-driven apps (Minecraft chat, games) get Esc +
        # digits. v0.5 uses printable keycodes only (upstream commit 82bca82b).
        # TODO: drop once nixpkgs ships wtype >= 0.5.
        wtype = upkgs.wtype.overrideAttrs {
          version = "0.5";
          src = pkgs.fetchFromGitHub {
            owner = "atx";
            repo = "wtype";
            rev = "v0.5";
            hash = "sha256-1Qf35RPfaMusP1WeLcwmvfmnCmaG/WZBoIlOewZakc4=";
          };
        };
        voxtypePkg = upkgs.voxtype-onnx.override {
          waylandRuntimePackages = [
            upkgs.dotool
            upkgs.wl-clipboard
            wtype
          ];
        };
        voxtype = lib.getExe voxtypePkg;
        model = "parakeet-tdt-0.6b-v3";
        configFile = (pkgs.formats.toml { }).generate "config.toml" {
          engine = "parakeet";
          parakeet.model = model;
          # Hyprland's press/release binds drive recording instead of evdev.
          hotkey.enabled = false;
          # nixpkgs builds no OSD frontend; without this the daemon crash-loops
          # spawning one on every start.
          osd.enabled = false;
          output = {
            mode = "type";
            fallback_to_clipboard = true;
            # Transcription lands in ~0.2s; if caps (= Super_R) is still held
            # then, typed letters become Hyprland shortcuts.
            pre_type_delay_ms = 300;
          };
        };
      in
      {
        home-manager.users.${user} = {
          home.packages = [ voxtypePkg ];
          xdg.configFile."voxtype/config.toml".source = configFile;
          # caps+e holds F19 (the only F13-F24 key xkb leaves as a plain
          # keysym). kanata keeps it down until e itself is released, whatever
          # order caps comes up in, and suppresses Super meanwhile -- so the
          # release bind always fires. Base layer only: per-app layers (ghostty)
          # keep their own caps+e.
          keyLayers.layers.base.capsbinds.keys.e.key = "f19";
          xdg.configFile."hypr/voxtype.lua".text = ''
            hl.bind("F19", hl.dsp.exec_cmd("${voxtype} record start"))
            hl.bind("F19", hl.dsp.exec_cmd("${voxtype} record stop"), { release = true })
          '';
          systemd.user.services.voxtype = {
            Unit = {
              Description = "Voxtype push-to-talk dictation";
              After = [ "graphical-session.target" ];
              PartOf = [ "graphical-session.target" ];
              # The daemon reads config.toml only at start, so restart it on change.
              X-Restart-Triggers = [ "${configFile}" ];
            };
            Service = {
              # Downloads the model on first start; a no-op once it is present.
              ExecStartPre = "${voxtype} setup --download --model ${model} --no-post-install";
              ExecStart = "${voxtype} daemon";
              Restart = "on-failure";
              RestartSec = 5;
            };
            Install.WantedBy = [ "graphical-session.target" ];
          };
        };
      }
    )

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

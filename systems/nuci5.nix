{
  inputs,
  hostname,
  lib,
  pkgs,
  self,
  user,
  config,
  ...
} @ args: {
  imports = [
    inputs.disko.nixosModules.disko
    ./hardware/disks/simple-disk.nix
    ./services/kdeconnect.nix

    inputs.determinate.nixosModules.default

    self.nixosModules.audio.pipewire
    self.nixosModules.home
    self.nixosModules.nix

    {
      services.udisks2.enable = true;
    }

    {
      security.sudo.extraRules = [
        {
          users = ["tv"];
          commands = [
            {
              command = "ALL";
              options = ["NOPASSWD" "SETENV"];
            }
          ];
        }
      ];
    }

    {
      services.sabnzbd = {
        enable = true;
      };

      services.jellyfin = {
        enable = true;
      };
    }
    {
      # No lock, no suspend - just turn screen off when idle
      home-manager.users.${user} = {
        # Inhibit idle when any audio is playing (Spotify, mpv, etc.)
        systemd.user.services.sway-audio-idle-inhibit = {
          Unit = {
            Description = "Inhibit idle when audio is playing";
            After = ["graphical-session.target"];
            PartOf = ["graphical-session.target"];
          };
          Service = {
            ExecStart = "${pkgs.sway-audio-idle-inhibit}/bin/sway-audio-idle-inhibit";
            Restart = "on-failure";
            RestartSec = 5;
          };
          Install.WantedBy = ["graphical-session.target"];
        };

        services.hypridle.settings = lib.mkForce {
          general = {
            after_sleep_cmd = "hyprctl dispatch dpms on";
          };

          listener = [
            {
              timeout = 600; # 10 minutes - screen off
              on-timeout = "hyprctl dispatch dpms off";
              on-resume = "hyprctl dispatch dpms on";
            }
          ];
        };
      };
    }

    self.nixosModules.hyprland
    self.nixosModules.desktop.noctalia
    {
      hardware.graphics = {
        enable = true;
        enable32Bit = true;
        extraPackages = with pkgs; [
          mesa
          intel-media-driver
          intel-vaapi-driver
          libdrm
        ];
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

      hardware.bluetooth = {
        enable = true;
        powerOnBoot = true;
        package = pkgs.bluez.override {enableExperimental = true;};
        settings = {
          General = {
            ControllerMode = "dual"; # BR/EDR + LE
            JustWorksRepairing = "always"; # Fix pairing issues
            Experimental = true; # Battery reports
            FastConnectable = true;
            ReconnectAttempts = 7;
          };
        };
        disabledPlugins = ["sap"]; # Disable SIM Access Profile
      };
      services.blueman.enable = true; # GUI manager
    }

    {
      hardware.steam-hardware.enable = true;

      hardware.graphics = {
        enable = true;
        enable32Bit = true;
      };

      services.pipewire.alsa.support32Bit = true;
    }
  ];

  # Prevent snd-usb-audio from claiming XING WEI 2.4G USB dongle (1915:1025).
  # It's a keyboard/mouse dongle with unnecessary audio interfaces that waste USB bandwidth.
  # HID interfaces (keyboard/mouse) are unaffected - only the audio driver is disabled.
  boot.extraModprobeConfig = ''
    options snd-usb-audio vid=0x1915 pid=0x1025 enable=0
  '';

  services.dbus.enable = true;

  hardware.uinput.enable = true;

  nix.settings.auto-optimise-store = true;

  networking.hostName = hostname;

  networking.firewall = {
    enable = false;
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

  boot = {
    kernelModules = [
      "i915"
      "cec" # HDMI-CEC support
      "drm" # DRM subsystem for CEC
    ];
    kernelParams = [
      "i915.modeset=1"
      "i915.preliminary_hw_support=1"
    ];
  };
  boot.loader.grub = {
    efiSupport = true;
    efiInstallAsRemovable = true;
  };
  services.openssh.enable = true;

  time.timeZone = "Europe/Berlin";

  environment.systemPackages = [
    pkgs.curl
    pkgs.gitMinimal

    inputs.nixgl.packages.x86_64-linux.nixGLIntel
  ];

  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJojYXf9Koo8FT/vWB+skUbrgWCkng158wJvHX0zJBXb selby@niko.ink"
  ];

  system.stateVersion = "24.11";
}

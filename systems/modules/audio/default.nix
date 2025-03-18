{ config, pkgs, ... }:

{
  # Core Audio Configuration
  hardware.pulseaudio.enable = false; # Use PipeWire, not PulseAudio
  security.rtkit.enable = true;       # Allow processes to use realtime priorities

  # Bluetooth Configuration
  hardware.bluetooth = {
    enable = true;
    package = pkgs.bluez.override {
      enableExperimental = true; # Enable experimental features for better codec support
    };
    settings = {
      General = {
        Enable = "Source,Sink,Media,Socket";
        ControllerMode = "dual";       # Allow both BR/EDR and LE modes
        JustWorksRepairing = "always";
        Privacy = "device";
        Experimental = true;
      };
    };
  };

  services.blueman.enable = true; # GUI tool for managing Bluetooth devices

  # PipeWire Configuration
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    jack.enable = true; # Enable JACK support for pro audio use-cases

    # WirePlumber configuration for Bluetooth and audio
    wireplumber.enable = true;
    wireplumber.extraConfig = {
      # Low-latency audio configuration
      "92-low-latency" = {
        "context.properties" = {
          "default.clock.rate" = 48000;
          "default.clock.quantum" = 64;     # Balanced setting for latency vs stability
          "default.clock.min-quantum" = 32;
          "default.clock.max-quantum" = 8192;
        };
      };

      # Bluetooth audio configuration
      "10-bluetooth-policy" = {
        "monitor.bluez.properties" = {
          "bluez5.enable" = true;
          "bluez5.headset-roles" = [ "hsp_hs" "hsp_ag" "hfp_hf" "hfp_ag" ];
          "bluez5.codecs" = [ "ldac" "aptx_hd" "aptx" "aac" "sbc_xq" "sbc" ];
          "bluez5.auto-connect" = [ "a2dp_sink" "hfp_hf" "hsp_hs" ];
          "bluez5.msbc-support" = true;     # Enable mSBC for better call quality
          "bluez5.sbc-xq-support" = true;   # Enable SBC XQ for better audio quality
          "bluez5.hfphsp-backend" = "native";  # Use native backend for HFP/HSP
        };
      };

      # Automatic profile switching for calls
      "20-bluetooth-switching" = {
        "monitor.bluez.rules" = [
          {
            matches = [ { "device.name" = "~bluez_card.*"; } ];
            actions = {
              update-props = {
                "bluez5.autoswitch-profile" = true;
                "bluez5.reconnect-profiles" = [ "hfp_hf" "hsp_hs" "a2dp_sink" ];
              };
            };
          }
        ];
      };

      # Enable auto-switching to newly connected audio devices
      "30-auto-connect" = {
        "device.properties" = {
          "device.nick" = "system";
        };
        "device.rules" = [
          {
            matches = [{ "device.name" = "~alsa_card.*"; }];
            actions = {
              update-props = {
                "device.nick" = "alsa-device";
                "device.description" = "ALSA Device";
              };
            };
          }
        ];
        "alsa.rules" = [
          {
            matches = [
              { "node.name" = "~alsa_output.*"; }
              { "node.name" = "~alsa_input.*"; }
            ];
            actions = {
              update-props = {
                "session.suspend-timeout-seconds" = 0;  # Disable node suspension
                "node.pause-on-idle" = false;
              };
            };
          }
        ];
      };

      # PulseAudio compatibility configuration
      "50-pulseaudio-compat" = {
        "pulse.properties" = {
          "server.address" = [ "unix:native" ];
          "vm.overrides" = {
            "pulse.min.quantum" = "1024/48000";
          };
        };
        "pulse.rules" = [
          {
            matches = [ { "application.name" = "~.*"; } ];
            actions = {
              update-props = {
                "pulse.adapt.suspend-timeout-seconds" = 0;
              };
            };
          }
        ];
      };
    };
  };

  # Udev Rules to avoid Bluetooth power-management issues
  services.udev.extraRules = ''
    # Disable autosuspend for Bluetooth adapters
    ACTION=="add", SUBSYSTEM=="bluetooth", ATTR{power/control}="on"
  '';

  # Kernel Parameters - Fix potential issues with audio hardware
  boot.kernelParams = [
    "snd_hda_intel.power_save=0"  # Prevent crackling on some Intel HD Audio devices
    "snd_hda_intel.dmic_detect=0" # Fix issues with some internal microphones
  ];

  # Install additional tools for managing and debugging audio/Bluetooth
  environment.systemPackages = with pkgs; [
    pavucontrol     # GUI volume control tool
    helvum          # Patchbay for PipeWire routing
    easyeffects     # Audio effects/equalizer GUI
    pamixer         # Command-line mixer tool
    bluez-tools     # Command-line Bluetooth utilities
    bluetuith       # TUI-based Bluetooth manager
    alsa-utils      # ALSA utilities (alsamixer, etc.)
  ];

  # Ensure the necessary firmware is available for Bluetooth adapters
  hardware.firmware = with pkgs; [
    firmwareLinuxNonfree
  ];
}


{ config, pkgs, lib, ... }:

{
  # ======================
  # Core Audio Stack
  # ======================
  hardware.pulseaudio.enable = false;  # Required for PipeWire
  security.rtkit.enable = true;        # Realtime priority management

  # ======================
  # PipeWire Configuration
  # ======================
  services.pipewire = {
    enable = true;

    # ALSA integration
    alsa = {
      enable = true;
      support32Bit = true;  # For legacy applications
    };

    # PulseAudio compatibility
    pulse.enable = true;

    # Professional audio support
    jack.enable = true;

    # WirePlumber configuration (replaces media-session)
    wireplumber = {
      enable = true;

      # Low-latency tuning
      configPackages = [
        (pkgs.writeTextDir "share/wireplumber/main.lua.d/99-lowlatency.lua" ''
          default_clock_rate = 48000
          default_clock_quantum = 64
          default_clock_min_quantum = 32
          default_clock_max_quantum = 8192

          alsa_monitor.properties = {
            ["alsa.jack-device"] = false,
            ["alsa.reserve"] = true,
            ["alsa.midi.rate"] = default_clock_rate
          }

          node_monitor.properties = {
            ["session.suspend-timeout-seconds"] = 0,
            ["node.pause-on-idle"] = false
          }
        '')
      ];
    };
  };

  # ======================
  # Kernel Tweaks
  # ======================
  boot.kernelParams = [
    "snd_hda_intel.power_save=0"   # Prevent audio crackling
    "snd_hda_intel.dmic_detect=0"  # Fix internal mic issues
  ];

  # ======================
  # Udev Rules
  # ======================
  services.udev.extraRules = ''
    # Prevent USB audio devices from suspending
    ACTION=="add", SUBSYSTEM=="sound", ATTR{power/control}="on"
  '';

  # ======================
  # Audio Tools
  # ======================
  environment.systemPackages = with pkgs; [
    # Control
    pavucontrol         # Volume mixer
    helvum              # Patchbay for routing
    qjackctl            # JACK control panel

    # Effects
    easyeffects         # System-wide effects
    calf                # Professional plugins

    # Diagnostics
    alsa-utils          # amixer, aplay, etc.
    pulseaudio-ctl      # CLI control
    sound-theme-freedesktop  # System sounds
  ];

  # ======================
  # Professional Audio
  # ======================
  environment.variables = {
    # JACK configuration
    JACK_NO_AUDIO_RESERVATION = "1";  # Better for consumer audio interfaces
    PIPEWIRE_LATENCY = "64/48000";     # Default latency
  };

  # Optional: Real-time privileges for audio group
  users.extraGroups.audio.extraRules = ''
    KERNEL=="rtc0", GROUP="audio"
    @audio - rtprio 95
    @audio - memlock unlimited
  '';
}


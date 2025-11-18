{pkgs, ...}: {
  services.pulseaudio.enable = false;
  security.rtkit.enable = true; # Realtime priority management

  services.pipewire = {
    enable = true;

    # ALSA integration
    alsa = {
      enable = true;
      support32Bit = true;
    };

    # PulseAudio compatibility
    pulse.enable = true;

    # Professional audio support
    jack.enable = true;

    # WirePlumber configuration (replaces media-session)
    wireplumber = {
      enable = true;

      # Fix audio crackling/popping in media players like mpv/VLC
      configPackages = [
        (pkgs.writeTextDir "share/wireplumber/main.lua.d/99-alsa-lowlatency.lua" ''
          alsa_monitor.properties = {
            -- Reduce buffer sizes to prevent crackling
            ["alsa.jackdbus-device"] = false,
            ["alsa.reserve"] = true,
            ["alsa.midi.rate"] = 48000,
          }

          alsa_monitor.rules = {
            {
              matches = {
                {
                  { "device.name", "matches", "alsa_card.*" },
                },
              },
              apply_properties = {
                ["api.alsa.period-size"] = 512,
                ["api.alsa.headroom"] = 8192,
                ["session.suspend-timeout-seconds"] = 0,
              },
            },
          }
        '')
      ];
    };
  };

  boot.kernelParams = [
    "snd_hda_intel.power_save=0" # Prevent audio crackling
    "snd_hda_intel.dmic_detect=0" # Fix internal mic issues
  ];

  # services.udev.extraRules = ''
  #   # Prevent USB audio devices from suspending
  #   ACTION=="add", SUBSYSTEM=="sound", ATTR{power/control}="on"
  # '';

  # Audio Tools
  environment.systemPackages = with pkgs; [
    # Control
    pavucontrol # Volume mixer
    helvum # Patchbay for routing
    qjackctl # JACK control panel

    # Effects
    easyeffects # System-wide effects
    calf # Professional plugins

    # Diagnostics
    alsa-utils # amixer, aplay, etc.
    pulseaudio-ctl # CLI control
    sound-theme-freedesktop # System sounds
  ];
}

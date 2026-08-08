{...}: {
  nixos = {pkgs, ...}: {
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
      wireplumber.enable = true;
    };

    boot.kernelParams = [
      "snd_hda_intel.power_save=0" # Prevent audio crackling
    ];

    # services.udev.extraRules = ''
    #   # Prevent USB audio devices from suspending
    #   ACTION=="add", SUBSYSTEM=="sound", ATTR{power/control}="on"
    # '';

    # Audio Tools
    environment.systemPackages = with pkgs; [
      # Control
      pavucontrol # Volume mixer
      crosspipe
      qjackctl # JACK control panel

      # Diagnostics
      alsa-utils # amixer, aplay, etc.
      sound-theme-freedesktop # System sounds
    ];
  };
}

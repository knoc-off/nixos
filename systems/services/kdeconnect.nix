{ pkgs, ... }:

{
  # Enable D-Bus, a prerequisite for almost all desktop services.
  services.dbus.enable = true;

  # Enable PipeWire for audio and screen sharing on Wayland.
  # This is the modern standard and replaces PulseAudio.
  services.pulseaudio.enable = false; # Disable PulseAudio
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    pulse.enable = true; # Provides a PulseAudio compatibility layer
  };


  # networking.firewall.allowedTCPPorts = [ 1714-1764 ];
  # networking.firewall.allowedUDPPorts = [ 1714-1764 ];
}

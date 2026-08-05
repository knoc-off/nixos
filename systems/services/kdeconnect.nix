_: {
  # Enable D-Bus, a prerequisite for almost all desktop services.
  services = {
    dbus.enable = true;

    pulseaudio.enable = false;
    pipewire = {
      enable = true;
      alsa.enable = true;
      pulse.enable = true;
    };
  };

  # networking.firewall.allowedTCPPorts = [ 1714-1764 ];
  # networking.firewall.allowedUDPPorts = [ 1714-1764 ];
}

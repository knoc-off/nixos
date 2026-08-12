{ pkgs, ... }:
{
  hardware.bluetooth = {
    enable = true;
    # AirPods use Just Works and fail to re-pair without this.
    settings.General.JustWorksRepairing = "always";
  };

  services.blueman.enable = true;

  systemd.user.services.mpris-proxy = {
    description = "Bluetooth MPRIS proxy";
    wantedBy = [ "default.target" ];
    serviceConfig = {
      ExecStart = "${pkgs.bluez}/bin/mpris-proxy";
      Restart = "on-failure";
    };
  };

  environment.systemPackages = with pkgs; [
    bluetuith
    bluez-tools
  ];
}

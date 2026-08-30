{ ... }: {
  nixos = { pkgs, ... }: {
    security.rtkit.enable = true;

    services.pipewire = {
      enable = true;

      alsa = {
        enable = true;
        support32Bit = true;
      };

      pulse.enable = true;

      # WirePlumber suspends idle nodes after 5s, which drops the A2DP
      # transport; re-acquiring it races and can leave the node in `error`,
      # dropping playback to the internal speakers.
      wireplumber.extraConfig."51-bluez-no-suspend"."monitor.bluez.rules" = [
        {
          matches = [ { "node.name" = "~bluez_output.*"; } ];
          actions.update-props."session.suspend-timeout-seconds" = 0;
        }
      ];
    };

    # Kernel default is 10s, which crackles on wake.
    boot.kernelParams = [ "snd_hda_intel.power_save=0" ];

    environment.systemPackages = with pkgs; [
      pavucontrol
      alsa-utils
    ];
  };
}

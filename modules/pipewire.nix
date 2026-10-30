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

      # Discord/WebRTC asks for ~360-frame buffers, which pulls the whole graph
      # to a 256-frame (5 ms) quantum. Easyeffects' DSP thread is not RT, so
      # under CPU load (a JVM at 900%) it misses that deadline and the output
      # chain xruns: audible buzz / channel desync. 1024 (21 ms) is inaudible
      # for voice chat and games.
      extraConfig.pipewire."10-min-quantum"."context.properties"."default.clock.min-quantum" = 1024;

      wireplumber.extraConfig = {
        # WirePlumber suspends idle nodes after 5s, which drops the A2DP
        # transport; re-acquiring it races and can leave the node in `error`,
        # dropping playback to the internal speakers.
        "51-bluez-no-suspend"."monitor.bluez.rules" = [
          {
            matches = [ { "node.name" = "~bluez_output.*"; } ];
            actions.update-props."session.suspend-timeout-seconds" = 0;
          }
        ];

        # spa/plugins/alsa/alsa-pcm.c names clocks "api.alsa.{p,c}-<card>", so
        # playback and capture of one HDA codec look like two unrelated clocks.
        # Whenever the mic is open (easyeffects keeps it open permanently) the
        # output becomes a rate-matched follower and periodically snd_pcm_rewind()s
        # to resync, which is audible as a buzz / channel desync. Giving both
        # directions the same clock.name skips the resampler between them.
        # Only the analog codec: HDMI PCMs live on a different card and clock.
        "51-hda-shared-clock"."monitor.alsa.rules" = [
          {
            matches = [ { "node.name" = "~alsa_(input|output)\\.pci-.*\\.analog-.*"; } ];
            actions.update-props."clock.name" = "hda-onboard";
          }
        ];
      };
    };

    # Kernel default is 10s, which crackles on wake.
    boot.kernelParams = [ "snd_hda_intel.power_save=0" ];

    environment.systemPackages = with pkgs; [
      pavucontrol
      alsa-utils
    ];
  };
}

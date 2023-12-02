{ inputs, pkgs, libs, config, ... }: {
  programs.mpv = {
    enable = true;
    bindings = {
      #WHEEL_UP = "seek 10";
      #WHEEL_DOWN = "seek -10";
      #"Alt+0" = "set window-scale 0.5";
    };
    config = {
      profile = "gpu-hq";
      force-window = true;
      ytdl-format = "bestvideo+bestaudio";
      cache-default = 4000000;
    };
    scripts = with pkgs.mpvScripts; [
      sponsorblock
      thumbnail

    ];
  };

}

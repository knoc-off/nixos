{
  inputs,
  ...
}: {
  # Prism launcher is better
  #poly = inputs.polymc.overlay;
  #nuenv = inputs.nuenv.overlays.default;

  # Backlink
  additions = final: _prev: import ../pkgs {pkgs = final;};

  modifications = final: prev: {

    spotiblock = prev.spotify.overrideAttrs (old: rec {
      postInstall = ''
        ExecMe="env LD_PRELOAD=${prev.spotify-adblock}/lib/libspotifyadblock.so spotify"

        sed -i "s|^TryExec=.*|TryExec=$ExecMe %U|" $out/share/applications/spotify.desktop
        sed -i "s|^Exec=.*|Exec=$ExecMe %U|" $out/share/applications/spotify.desktop
      '';

    });

    steam-scaling = prev.steamPackages.steam-fhsenv.override (old: rec {
      #pname = prev.steamPackages.steam-fhsenv.pname + "-scaling";
      extraArgs = (old.extraArgs or "") + " -forcedesktopscaling 1.0 ";
      #postInstall = ''
      #  sed -i 's/Exec=steam/Exec=steam -forcedesktopscaling 1.0/g' $out/share/applications/steam.desktop
      #'';
    });

    #pname = old.pname + "-scaling";
    #extraArgs = old.extraArgs ++ [ "-forcedesktopscaling 1.0" ];
  };

  #helloBar = pkgs.hello.overrideAttrs (finalAttrs: previousAttrs: {
  #  pname = previousAttrs.pname + "-bar";
  #});
}

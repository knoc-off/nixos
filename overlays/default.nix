{
  ...
}: {

  # Backlink
  additions = final: _prev: import ../pkgs {pkgs = final;};

  modifications = _final: prev: {

    spotiblock = prev.spotify.overrideAttrs (_old: rec {
      postInstall = ''
        ExecMe="env LD_PRELOAD=${prev.spotify-adblock}/lib/libspotifyadblock.so spotify"
        sed -i "s|^TryExec=.*|TryExec=$ExecMe %U|" $out/share/applications/spotify.desktop
        sed -i "s|^Exec=.*|Exec=$ExecMe %U|" $out/share/applications/spotify.desktop
      '';
    });

    steam-scaling = prev.steamPackages.steam-fhsenv.override (old: rec {
      extraArgs = (old.extraArgs or "") + " -forcedesktopscaling 1.0 ";
    });

  };

}

{
  inputs,
  ...
}: {

  # Backlink
  #additions = final: _prev: import ../pkgs {pkgs = final;};
  # Adds my custom packages
  additions = final: prev:
    import ../pkgs {
      inherit inputs;

      pkgs = final;
    };


  #additions = final: prev:
  #  let
  #    flakePlaygroundPackages = final.flakePlayground.packages.${final.system};
  #  in



  modifications = _final: prev: {

    #spotiblock = prev.spotify.overrideAttrs (_old: rec {
    #  postInstall = ''
    #    ExecMe="env LD_PRELOAD=${prev.spotify-adblock}/lib/libspotifyadblock.so spotify"
    #    sed -i "s|^TryExec=.*|TryExec=$ExecMe %U|" $out/share/applications/spotify.desktop
    #    sed -i "s|^Exec=.*|Exec=$ExecMe %U|" $out/share/applications/spotify.desktop
    #  '';
    #});

    steam-scaling = prev.steamPackages.steam-fhsenv.override (old: rec {
      extraArgs = (old.extraArgs or "") + " -forcedesktopscaling 1.0 ";
    });


    unstable-packages = final: _prev: {
      unstable = import inputs.nixpkgs-unstable {
        system = final.system;
        config.allowUnfree = true;
      };
    };

  };

}

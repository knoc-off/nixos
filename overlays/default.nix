{inputs, ...}: {
  additions = final: prev:
    import ../pkgs {
      inherit inputs;
      pkgs = final;
    };

  modifications = _final: prev: {
    spotiblock = prev.spotify.overrideAttrs (_old: {
      postInstall = ''
        ExecMe="env LD_PRELOAD=${prev.spotify-adblock}/lib/libspotifyadblock.so spotify"
        sed -i "s|^TryExec=.*|TryExec=$ExecMe %U|" $out/share/applications/spotify.desktop
        sed -i "s|^Exec=.*|Exec=$ExecMe %U|" $out/share/applications/spotify.desktop
      '';
    });

    steam-scaling = prev.steamPackages.steam-fhsenv.override (old: {
      extraArgs = (old.extraArgs or "") + " -forcedesktopscaling 1.0 ";
    });

    unstable-packages = final: _prev: {
      unstable = import inputs.nixpkgs-unstable {
        inherit (final) system;
        config.allowUnfree = true;
      };
    };
  };
}

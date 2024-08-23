{inputs, ...}: {
  #additions = final: prev:
  #  import ../pkgs {
  #    inherit inputs;
  #    pkgs = final;
  #  };

  modifications = _final: prev: {

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

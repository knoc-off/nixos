{ inputs, ... }: {
  # Local build helpers, exposed in pkgs.* alongside writeShellScript and
  # friends. These are functions, not packages, so they deliberately do not
  # live in ./pkgs -- everything discovered there is expected to be a
  # derivation.
  builders = final: _prev: {
    writeLuaScript = final.callPackage ./builders/write-lua-script.nix { };
    writeNuScript = final.callPackage ./builders/write-nu-script.nix { };
    mkComplgenScript = final.callPackage ./builders/mk-complgen-script.nix { };
  };

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

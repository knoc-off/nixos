{inputs, ...}: {
  # Local build helpers, exposed in pkgs.* alongside writeShellScript and
  # friends. These are functions, not packages, so they deliberately do not
  # live in ./pkgs -- everything discovered there is expected to be a
  # derivation (see lib.flattenDrvs).
  builders = final: _prev: {
    writeLuaScript = final.callPackage ./builders/write-lua-script.nix {};
    writeNuScript = final.callPackage ./builders/write-nu-script.nix {};
    mkComplgenScript = final.callPackage ./builders/mk-complgen-script.nix {};
  };

  # lib/color-lib.nix calls builtins.wasm, which exists only in Determinate
  # Nix -- the stock evaluator dies with "attribute 'wasm' missing" before it
  # reaches anything else. Having Determinate installed is not enough: any
  # tool that links its own libnixexpr evaluates with *that* copy, not with
  # whatever is on PATH.
  #
  # nixpkgs' nix-eval-jobs links upstream nix via nixComponents, and
  # nix-fast-build prepends both nix-eval-jobs and nix-eval-jobs.nix to its
  # wrapper PATH -- so the build farm evaluated every host with a stock
  # evaluator and failed on color-lib.
  #
  # Overriding nixpkgs' nixComponents with Determinate's does not compile:
  # Determinate's NixStringContextElem carries a Path variant that upstream
  # nix-eval-jobs 2.34.1's std::visit overload set does not cover, so
  # extractConstituents fails to instantiate. Determinate maintain a fork on
  # the `detsys` branch that tracks their nix-src; it is pinned in flake.nix
  # with its `nix` input following ours, so the evaluator it links is
  # exactly the one the system runs.
  #
  # nix-fast-build picks this up transitively via nix-eval-jobs.passthru.nix,
  # which nixpkgs' package sets but the fork does not -- so it is added here.
  #
  # pkgs/nixos-anywhere.nix works around the same root cause; see there.
  determinate-eval = final: _prev: {
    nix-eval-jobs =
      inputs.nix-eval-jobs-determinate.packages.${final.stdenv.hostPlatform.system}.default.overrideAttrs
      (old: {
        passthru = (old.passthru or {}) // {
          inherit (old.passthru.nixComponents) nix-cli;
          nix = old.passthru.nixComponents.nix-cli;
        };
      });
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

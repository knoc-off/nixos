{ ... }: {
  # Local build helpers, exposed in pkgs.* alongside writeShellScript and
  # friends. These are functions, not packages, so they deliberately do not
  # live in ./pkgs -- everything discovered there is expected to be a
  # derivation.
  builders = final: _prev: {
    mkComplgenScript = final.callPackage ./builders/mk-complgen-script.nix { };
  };
}

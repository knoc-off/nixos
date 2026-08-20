{
  lib ? import <nixpkgs/lib>,
}:
let
  color-lib = import ./color-lib.nix { inherit lib; };
in
{
  inherit color-lib;
  theme = import ../theme.nix { inherit lib color-lib; };

  # Per-window kanata/hyprkan key layers: { mkKeyLayers; presets; }
  keyLayers = import ./key-layers.nix { inherit lib; };

  # Headscale-assigned tailnet IPs, by host.
  tailnet = import ./tailnet.nix;
  ssh = import ./ssh.nix;

  # rust-analyzer settings shared by neovim and opencode, so that whichever
  # client initializes a shared lspmux session proposes the same config.
  rustAnalyzerSettings = import ./rust-analyzer-settings.nix;

  # Recursively discover packages from a directory tree.
  # - foo.nix (not default.nix) -> { foo = pkgs.callPackage ./foo.nix {}; }
  # - bar/ with default.nix     -> { bar = pkgs.callPackage ./bar {}; }   (leaf package)
  # - baz/ without default.nix  -> { baz = <recurse into baz/>; }
  # Skips hidden entries (starting with ".").
  discoverPackages =
    pkgs:
    let
      discover =
        dir:
        lib.pipe (builtins.readDir dir) [
          (lib.filterAttrs (name: _: name != "default.nix" && !lib.hasPrefix "." name))
          (lib.mapAttrs' (
            name: type:
            if type == "regular" && lib.hasSuffix ".nix" name then
              {
                name = lib.removeSuffix ".nix" name;
                value = pkgs.callPackage (dir + "/${name}") { };
              }
            else if type == "directory" && builtins.pathExists (dir + "/${name}/default.nix") then
              {
                name = name;
                value = pkgs.callPackage (dir + "/${name}") { };
              }
            else if type == "directory" then
              {
                name = name;
                value = discover (dir + "/${name}");
              }
            else
              {
                name = name;
                value = null;
              }
          ))
          (lib.filterAttrs (_: v: v != null))
        ];
    in
    discover;

  # Flatten a package tree into a single level of derivations, keyed by
  # "namespace/name".
  #
  # This mirrors discoverPackages' own rule -- a directory without default.nix
  # is a namespace, everything else is a package -- and enforces the invariant
  # that every leaf under ./pkgs is a derivation. Anything else is an error
  # rather than a silent omission: a package that quietly evaluates to a
  # non-derivation (an empty directory, a builder function left in the tree)
  # would otherwise vanish from the build farm without a trace.
  flattenDrvs =
    let
      flatten =
        prefix: attrs:
        lib.concatMapAttrs (
          name: value:
          let
            path = if prefix == "" then name else "${prefix}/${name}";
          in
          if lib.isDerivation value then
            { ${path} = value; }
          else if lib.isAttrs value && !(value ? __functor) then
            flatten path value
          else
            throw "pkgs/${path} is a ${builtins.typeOf value}, not a derivation or a namespace. Builders belong in overlays/, raw assets belong next to the module that uses them."
        ) attrs;
    in
    flatten "";

  # Recursively discover nix modules from a directory tree.
  # - foo.nix (not default.nix) -> { foo = import foo.nix; }
  # - bar/ with default.nix     -> { bar = import bar/; }   (leaf module)
  # - baz/ without default.nix  -> { baz = <recurse into baz/>; }
  discoverModules =
    let
      discover =
        dir:
        lib.pipe (builtins.readDir dir) [
          (lib.filterAttrs (name: _: name != "default.nix"))
          (lib.mapAttrs' (
            name: type:
            if type == "regular" && lib.hasSuffix ".nix" name then
              {
                name = lib.removeSuffix ".nix" name;
                value = import (dir + "/${name}");
              }
            else if type == "directory" && builtins.pathExists (dir + "/${name}/default.nix") then
              {
                name = name;
                value = import (dir + "/${name}");
              }
            else if type == "directory" then
              {
                name = name;
                value = discover (dir + "/${name}");
              }
            else
              {
                name = name;
                value = null;
              }
          ))
          (lib.filterAttrs (_: v: v != null))
        ];
    in
    discover;

  # Discover dendritic aspect modules from a directory tree.
  # Each module file is a function: { inputs, self } -> { nixos?, home? }
  # Returns { nixos = <nested attrset of NixOS modules>; home = <nested attrset of HM modules>; }
  #
  # Tree-walking rules are the same as discoverModules, but each leaf is
  # called with { inputs, self } and the result is split by side.
  discoverAspects =
    { inputs, self }:
    let
      isAspect = v: lib.isAttrs v && (v ? nixos || v ? home);

      discover =
        dir:
        lib.pipe (builtins.readDir dir) [
          (lib.filterAttrs (name: _: name != "default.nix" && !lib.hasPrefix "." name))
          (lib.mapAttrs' (
            name: type:
            if type == "regular" && lib.hasSuffix ".nix" name then
              {
                name = lib.removeSuffix ".nix" name;
                value = import (dir + "/${name}") { inherit inputs self; };
              }
            else if type == "directory" && builtins.pathExists (dir + "/${name}/default.nix") then
              {
                name = name;
                value = import (dir + "/${name}") { inherit inputs self; };
              }
            else if type == "directory" then
              {
                name = name;
                value = discover (dir + "/${name}");
              }
            else
              {
                name = name;
                value = null;
              }
          ))
          (lib.filterAttrs (_: v: v != null))
        ];

      # Recursively extract one side (nixos or home) from the discovered tree.
      extractSide =
        side: tree:
        lib.pipe tree [
          (lib.mapAttrs (
            _: value:
            if isAspect value then
              value.${side} or null
            else if lib.isAttrs value then
              let
                sub = extractSide side value;
              in
              if sub == { } then null else sub
            else
              null
          ))
          (lib.filterAttrs (_: v: v != null))
        ];

      raw = discover;
    in
    dir:
    let
      tree = raw dir;
    in
    {
      nixos = extractSide "nixos" tree;
      home = extractSide "home" tree;
    };
}

{
  lib ? import <nixpkgs/lib>,
}:
let
  color-lib = import ./color-lib/color-manipulation.nix { inherit lib; };
in
{
  inherit color-lib;
  theme = import ../theme.nix { inherit lib color-lib; };

  # Per-window kanata + Hyprland key layers: { mkKeyLayers; presets; }
  keyLayers = import ./key-layers.nix { inherit lib; };

  # Headscale-assigned tailnet IPs, by host.
  tailnet = import ./tailnet.nix;
  ssh = import ./ssh.nix;
  nixCache = import ./nix-cache.nix;

  # rust-analyzer settings shared by neovim and opencode, so that whichever
  # client initializes a shared lspmux session proposes the same config.
  rustAnalyzerSettings = import ./rust-analyzer-settings.nix;

  # Recursively discover packages from a directory tree.
  # - foo.nix (not default.nix) -> { foo = pkgs.callPackage ./foo.nix {}; }
  # - bar/ with default.nix     -> { bar = pkgs.callPackage ./bar {}; }   (leaf package)
  # - baz/ without default.nix  -> { baz = <recurse into baz/>; }
  # Skips hidden entries (starting with ".").
  #
  # Filtering happens on readDir's name/type *before* building the value
  # thunks, not by building every value and dropping the nulls afterward --
  # the latter forces every package in the tree to WHNF just to find out
  # which ones exist, which breaks any package that references
  # self.packages.${system} (a common pattern for dropping ../backlinks
  # between sibling packages): forcing it needs the very attrset currently
  # under construction.
  discoverPackages =
    pkgs:
    let
      discover =
        dir:
        lib.pipe (builtins.readDir dir) [
          (lib.filterAttrs (
            name: type:
            name != "default.nix"
            && !lib.hasPrefix "." name
            && (type == "directory" || (type == "regular" && lib.hasSuffix ".nix" name))
          ))
          (lib.mapAttrs' (
            name: type:
            if type == "regular" then
              {
                name = lib.removeSuffix ".nix" name;
                value = pkgs.callPackage (dir + "/${name}") { };
              }
            else if builtins.pathExists (dir + "/${name}/default.nix") then
              {
                name = name;
                value = pkgs.callPackage (dir + "/${name}") { };
              }
            else
              {
                name = name;
                value = discover (dir + "/${name}");
              }
          ))
        ];
    in
    discover;

  # Discover dendritic aspect modules from a directory tree.
  # Each module file is a function: { inputs, self } -> { nixos?, home? }
  # Returns { nixos = <nested attrset of NixOS modules>; home = <nested attrset of HM modules>; }
  #
  # Tree-walking rules are the same as discoverPackages, but each leaf is
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

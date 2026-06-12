{lib ? import <nixpkgs/lib>}: let
  color-lib = import ./color-lib.nix {inherit lib;};
in {
  inherit color-lib;
  theme = import ../theme.nix {inherit lib color-lib;};

  # Per-window kanata/hyprkan key layers: { mkKeyLayers; presets; }
  keyLayers = import ./key-layers.nix {inherit lib;};

  # Recursively discover packages from a directory tree.
  # - foo.nix (not default.nix) -> { foo = pkgs.callPackage ./foo.nix {}; }
  # - bar/ with default.nix     -> { bar = pkgs.callPackage ./bar {}; }   (leaf package)
  # - baz/ without default.nix  -> { baz = <recurse into baz/>; }
  # Skips hidden entries (starting with ".").
  discoverPackages = pkgs: let
    discover = dir:
      lib.pipe (builtins.readDir dir) [
        (lib.filterAttrs (name: _: name != "default.nix" && !lib.hasPrefix "." name))
        (lib.mapAttrs' (
          name: type:
            if type == "regular" && lib.hasSuffix ".nix" name
            then {
              name = lib.removeSuffix ".nix" name;
              value = pkgs.callPackage (dir + "/${name}") {};
            }
            else if type == "directory" && builtins.pathExists (dir + "/${name}/default.nix")
            then {
              name = name;
              value = pkgs.callPackage (dir + "/${name}") {};
            }
            else if type == "directory"
            then {
              name = name;
              value = discover (dir + "/${name}");
            }
            else {
              name = name;
              value = null;
            }
        ))
        (lib.filterAttrs (_: v: v != null))
      ];
  in
    discover;

  # Recursively discover nix modules from a directory tree.
  # - foo.nix (not default.nix) -> { foo = import foo.nix; }
  # - bar/ with default.nix     -> { bar = import bar/; }   (leaf module)
  # - baz/ without default.nix  -> { baz = <recurse into baz/>; }
  discoverModules = let
    discover = dir:
      lib.pipe (builtins.readDir dir) [
        (lib.filterAttrs (name: _: name != "default.nix"))
        (lib.mapAttrs' (
          name: type:
            if type == "regular" && lib.hasSuffix ".nix" name
            then {
              name = lib.removeSuffix ".nix" name;
              value = import (dir + "/${name}");
            }
            else if type == "directory" && builtins.pathExists (dir + "/${name}/default.nix")
            then {
              name = name;
              value = import (dir + "/${name}");
            }
            else if type == "directory"
            then {
              name = name;
              value = discover (dir + "/${name}");
            }
            else {
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
  discoverAspects = {inputs, self}: let
    isAspect = v: lib.isAttrs v && (v ? nixos || v ? home);

    discover = dir:
      lib.pipe (builtins.readDir dir) [
        (lib.filterAttrs (name: _: name != "default.nix" && !lib.hasPrefix "." name))
        (lib.mapAttrs' (
          name: type:
            if type == "regular" && lib.hasSuffix ".nix" name
            then {
              name = lib.removeSuffix ".nix" name;
              value = import (dir + "/${name}") {inherit inputs self;};
            }
            else if type == "directory" && builtins.pathExists (dir + "/${name}/default.nix")
            then {
              name = name;
              value = import (dir + "/${name}") {inherit inputs self;};
            }
            else if type == "directory"
            then {
              name = name;
              value = discover (dir + "/${name}");
            }
            else {
              name = name;
              value = null;
            }
        ))
        (lib.filterAttrs (_: v: v != null))
      ];

    # Recursively extract one side (nixos or home) from the discovered tree.
    extractSide = side: tree:
      lib.pipe tree [
        (lib.mapAttrs (_: value:
          if isAspect value then
            value.${side} or null
          else if lib.isAttrs value then
            let sub = extractSide side value;
            in if sub == {} then null else sub
          else null
        ))
        (lib.filterAttrs (_: v: v != null))
      ];

    raw = discover;
  in
    dir: let tree = raw dir; in {
      nixos = extractSide "nixos" tree;
      home = extractSide "home" tree;
    };
}

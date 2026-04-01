{lib ? import <nixpkgs/lib>}: let
  color-lib = import ./color-lib.nix {inherit lib;};
in {
  inherit color-lib;
  math = import ./math.nix {inherit lib;};
  theme = import ../theme.nix {inherit lib color-lib;};

  # Recursively discover packages from a directory tree.
  # - foo.nix (not default.nix) -> { foo = pkgs.callPackage ./foo.nix {}; }
  # - bar/ with default.nix     -> { bar = pkgs.callPackage ./bar {}; }   (leaf package)
  # - baz/ without default.nix  -> { baz = <recurse into baz/>; }
  # Skips hidden entries (starting with ".").
  discoverPackages = pkgs: let
    discover = dir:
      lib.pipe (builtins.readDir dir) [
        (lib.filterAttrs (name: _: name != "default.nix" && !lib.hasPrefix "." name))
        (lib.mapAttrs' (name: type:
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
        (lib.mapAttrs' (name: type:
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
}

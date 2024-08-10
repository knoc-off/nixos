{ pkgs ? import <nixpkgs> {} }:

import ./filter-concat.nix { inherit pkgs; }

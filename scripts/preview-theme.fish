#!/usr/bin/env fish
# Preview the current theme.nix palette in the terminal with colored swatches.
# Usage: fish /etc/nixos/scripts/preview-theme.fish [dark|light|both]

set -l mode (string lower -- $argv[1])
test -z "$mode"; and set mode both

set -l script_dir (status dirname)
nix eval --impure --raw --apply "f: f { variant = \"$mode\"; }" --file "$script_dir/preview-theme.nix"
echo ""

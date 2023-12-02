#! /usr/bin/env nix-shell
#! nix-shell -i bash -p bash



set -euo pipefail

# get the configs from the flake
nix flake show | grep -E "nixos-config|nixpkgs-overlays"




# ip address
read -p "Enter the ip address: " ip

# check if the ip address is valid
if [[ ! $ip =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Invalid ip address"
    exit 1
fi

# check if the ip address is reachable
if ! ping -c 1 $ip &> /dev/null; then
    echo "Ip address not reachable"
    exit 1
fi


nix run github:nix-community/nixos-anywhere -- --flake .#host root@$ip

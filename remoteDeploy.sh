#!/usr/bin/env nix-shell
#!nix-shell -i bash -p git jq

set -euo pipefail

function selectConfig() {

    configs=$(nix flake show --json | jq -r '.nixosConfigurations')

    # get the names of the configs
    names=$(echo "$configs" | jq -r 'keys[]')

    # select the config
    i=0
    for name in $names; do
        echo "$i: $name"
        i=$((i+1))
    done

    read -rp "Select the config: " num

    # check if the input is valid
    if [[ ! $i =~ ^[0-9]+$ ]]; then
        >&2 echo "Invalid input"
        exit 1
    fi

    # get the name of the config
    # bash array, num is the index
    i=0
    for name in $names; do
        if [[ $i == "$num" ]]; then
            config=$name
            break
        fi
        i=$((i+1))
    done
}

function selectComputer() {
    # ip address
    read -rp "Enter the ip address: " ip

    # check if the ip address is valid
    if [[ ! $ip =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        >&2 echo "Invalid ip address"
        exit 1
    fi

    echo "$ip"
}

# if argument is not -y or --yes, then ask the user if he wants to use the last options
yn="y"

# check if the argument is not empty
if [[ -f .remoteDeployOptions ]] && [[ ! $# -gt 0 ]] || [[ $1 != "-y" && $1 != "--yes" ]]; then
    # list contents of .remoteDeployOptions
    jq . .remoteDeployOptions
    read -rp "Do you want to use the last options? [Y/n] " yn
fi

# if Y, y or blank, then restore the options
if [[ $yn == "Y" || $yn == "y" || $yn == "" ]]; then
    # restore the options from the last run
    if [[ -f .remoteDeployOptions ]]; then
        options=$(cat .remoteDeployOptions)
        config=$(echo "$options" | jq -r '.config')
        ip=$(echo "$options" | jq -r '.ip')
    else
        >&2 echo "No options to restore"
        exit 1
    fi
else
    # get the config
    selectConfig
    ip=$(selectComputer)
    jq -n --arg config "$config" --arg ip "$ip" '{"config": $config, "ip": $ip}' > .remoteDeployOptions

fi

eval "nixos-rebuild switch -j auto --use-remote-sudo --target-host root@$ip --flake .#$config"

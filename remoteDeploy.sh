#!/usr/bin/env nix-shell
#!nix-shell -i bash -p git jq

set -euo pipefail

function selectConfig() {

    configs=$(nix flake show --json | jq -r '.nixosConfigurations')
    # get the names of the configs
    names=$(echo $configs | jq -r 'keys[]')



    # select the config
    i=0
    for name in $names; do
        echo "$i: $name"
        i=$((i+1))
    done

    read -p "Select the config: " num

    # check if the input is valid
    if [[ ! $i =~ ^[0-9]+$ ]]; then
        echo "Invalid input"
        exit 1
    fi

    # get the name of the config
    # bash array, num is the index
    i=0
    for name in $names; do
        if [[ $i == $num ]]; then
            config=$name
            break
        fi
        i=$((i+1))
    done

}

function selectComputer() {
    # use nmap to scan the network
    # get the ip addresses of the devices
    # first get the ip structure of the network
    # should output something like 192.168.XXX.0/24
#    ip=$(ip route | grep default | awk '{print $3}')
#    ip=${ip%.*}.0/24
#
#    nmap -sn $ip


    # nix-shell -p nmap --run "nmap -sn 192.168.16.0/24"
    # sho

#    devices=$(nmap -sn )

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
    echo $ip
}

# if argument is -y or --yes, then use the last options

if [[ ! $1 == "-y" || ! $1 == "--yes" ]]; then
    read -p "Do you want to use the last options? [Y/n] " yn
fi

if [[ $yn == "n" ]]; then
    # get the config
    selectConfig
    ip=$(selectComputer)
    # save the options,  so that they can be used in the next run, if the user wants to
    # format with jq. and save to local hidden file
    jq -n --arg config "$config" --arg ip "$ip" '{"config": $config, "ip": $ip}' > .remoteDeployOptions
else
    # restore the options from the last run
    if [[ -f .remoteDeployOptions ]]; then
        options=$(cat .remoteDeployOptions)
        config=$(echo $options | jq -r '.config')
        ip=$(echo $options | jq -r '.ip')
    fi
fi


nixos-rebuild switch -j auto --use-remote-sudo --target-host root@$ip --flake ".#$config"


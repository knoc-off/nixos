#! /usr/bin/env nix-shell
#! nix-shell -i bash -p bash curl git gnupg jq


# Set basic variables
# this makes the script exit if any command fails
set -e
# exit if any command returns a non-zero exit code
set -u
# if any command in a pipeline fails, that return code will be used as the return code of the whole pipeline
set -o pipefail



function download() {

    # remove directory if it exists
    rm -rf /tmp/config

    mkdir -p /tmp/config
    # get user input for the download
    # first get username
    # then get repo name
    # assume repo is github, but allow for other git repos, github if null.
    # then get branch name
    #
    # is it on github?

    read -p "Is the repo on github? [y/n] " github

    read -p "Enter the username: " username

    if [ -z "$username" ]; then
        username="knoc-off";
    fi

    read -p "Enter the repo name: " repo

    if [ -z "$repo" ]; then
        repo="nixos-config";
    fi


    if [ $github == "y" ]; then
        echo "Downloading from github"
        #git clone git@github.com:${username}/${repo}.git /tmp/config
        git clone https://github.com/${username}/${repo}.git /tmp/config
    else
        echo "Downloading from ${github}"
        #git clone git@${github}:${username}/${repo}.git /tmp/config
        git clone https://${github}/${username}/${repo}.git /tmp/config
    fi
}


function disk() {
    # in the repo, there should be a few disk config files, these are all in the
    # nixos-config/systems/disks folder
    # the user should be able to choose which one to use, in a dropdown

    # get the list of disk.nix files
    # find them in the repo: nixos-config/systems/disks/*.nix
    # then print them out in a list
    # then get user input for which one to use (number)
    # then copy that file to /tmp/configs/disk.nix

    # get the list of disk.nix files
    files=$(find /tmp/config/systems/hardware/disks/*.nix)
    # then print them out in a list
    echo "Choose a disk config file:"
    echo "--------------------------"
    # loop through the files and print them out with a number
    # use number as index to access file
    i=0
    for file in $files; do
        echo "${i}: ${file}"
        #files[$i]=$file
        i=$((i+1))
    done

    echo "--------------------------"
    # then get user input for which one to use (number)
    read -p "Enter the number of the disk config file to use: " file
    diskoconf="${files[$file]}"
    #cp ${files[$file]} /tmp/disk.nix


    if [ -z "$diskoconf" ]; then
        echo "Disk config cannot be empty"
        exit 1
    fi

    # last chance to abort
    read -p "Are you sure you want to use ${diskoconf}? [y/n] " confirm
    # allow lowercase or uppercase

    if [ $confirm != "y" ] && [ $confirm != "Y" ]; then
        echo "Aborting"
        exit 1
    fi
    nix --extra-experimental-features nix-command --extra-experimental-features flakes run github:nix-community/disko -- --mode disko ${diskoconf}

}


function init() {
    # Partition the disks


    # move the configs from the /tmp/configs folder to the /mnt/etc/nixos folder
    mkdir -p /mnt/etc/nixos
    mv /tmp/config/* /mnt/etc/nixos -r
    # then run nixos-install
    read -p "Enter the hostname: " hostname
    if [ -z "$hostname" ]; then
        echo "Hostname cannot be empty"
        exit 1
    fi
    nixos-install --root /mnt --flake /mnt/etc/nixos#${hostname}
    # then reboot
    #reboot

}

function main() {
    # download the config
    read -p "Download config? [y/n] " download
    if [ $download == "y" ]; then
        download
    fi
    # get the disk config
    disk
    # init the system
    init
}


main

#nix run github:nix-community/disko -- --mode disko /tmp/configs/disko-conf.nix


#nixos-generate-config --no-filesystems --root /mnt






#!/usr/bin/env bash

# Script to find and remove duplicate NixOS system generations based on labels in boot.json

# Ensure the script is run as root
if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root to access system generations."
    exit 1
fi

echo "Using system profile: /nix/var/nix/profiles/system"
echo

# Get list of generations
generations=$(nix-env --list-generations -p /nix/var/nix/profiles/system | awk '{print $1}')

declare -A label_to_gens

echo "Processing generations to find duplicates based on labels..."
echo

for gen in $generations; do
    # Get the path to the boot.json file
    gen_path="/nix/var/nix/profiles/system-${gen}-link"
    boot_json="${gen_path}/boot.json"
    if [ -f "$boot_json" ]; then
        # Extract the label using jq
        label=$(jq -r '.["org.nixos.bootspec.v1"].label' "$boot_json")
        # If label extraction fails or is null, set it to an empty string
        if [ -z "$label" ] || [ "$label" = "null" ]; then
            label="[No Label]"
        fi
    else
        label="[No boot.json]"
    fi
    echo "Generation $gen Label: $label"
    # Build an associative array mapping labels to generations
    label_to_gens["$label"]+="$gen "
done

echo
echo "Identifying duplicates..."
duplicates_found=false
for label in "${!label_to_gens[@]}"; do
    gens=${label_to_gens["$label"]}
    gens_array=($gens)
    if [ ${#gens_array[@]} -gt 1 ]; then
        duplicates_found=true
        # Sort the gens_array numerically to find the latest
        sorted_gens=($(printf '%s\n' "${gens_array[@]}" | sort -n))
        latest_gen=${sorted_gens[-1]}
        duplicate_gens=("${sorted_gens[@]:0:${#sorted_gens[@]}-1}")
        echo "Label: $label"
        echo "Latest generation to keep: $latest_gen"
        echo "Duplicate generations to delete: ${duplicate_gens[*]}"
        echo
    fi
done

if ! $duplicates_found; then
    echo "No duplicate generations found based on labels."
    exit 0
fi

# Prompt user for deletion
read -p "Do you want to delete the duplicate generations listed above? [y/N]: " answer
if [[ "$answer" =~ ^[Yy]$ ]]; then
    for label in "${!label_to_gens[@]}"; do
        gens=${label_to_gens["$label"]}
        gens_array=($gens)
        if [ ${#gens_array[@]} -gt 1 ]; then
            # Sort the gens_array numerically to find the latest
            sorted_gens=($(printf '%s\n' "${gens_array[@]}" | sort -n))
            latest_gen=${sorted_gens[-1]}
            duplicate_gens=("${sorted_gens[@]:0:${#sorted_gens[@]}-1}")
            for gen_to_delete in "${duplicate_gens[@]}"; do
                echo "Deleting generation $gen_to_delete..."
                nix-env --delete-generations -p /nix/var/nix/profiles/system "$gen_to_delete"
            done
        fi
    done
    echo "Duplicate generations have been deleted."
else
    echo "No changes made. Exiting."
fi


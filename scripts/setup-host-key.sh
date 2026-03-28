#!/usr/bin/env bash
# Generates an SSH host key for a NixOS system and converts it to an age key
# for use with sops-nix. Guides the user through updating .sops.yaml, then
# runs sops updatekeys to re-encrypt secrets for the new key.
#
# Usage:
#   ./scripts/setup-host-key.sh <hostname>
#
# Example:
#   ./scripts/setup-host-key.sh rpi-3a-plus
#
# The SSH host key is saved to a temp directory. It will be lost on reboot,
# so use it (e.g., inject into an image) before then.

set -euo pipefail

HOSTNAME="${1:?Usage: $0 <hostname>}"
SECRETS_FILE="systems/secrets/${HOSTNAME}/default.yaml"
SOPS_YAML=".sops.yaml"

# Verify we're in the flake root
if [[ ! -f "$SOPS_YAML" ]]; then
  echo "Error: $SOPS_YAML not found. Run this from the flake root (/etc/nixos)."
  exit 1
fi

# Check secrets file exists
if [[ ! -f "$SECRETS_FILE" ]]; then
  echo "Error: $SECRETS_FILE not found."
  echo "Create the secrets file first, or check the hostname."
  exit 1
fi

# Create temp directory for the key
KEY_DIR=$(mktemp -d)
KEY_PATH="${KEY_DIR}/ssh_host_ed25519_key"

echo "=== Generating SSH host key for '${HOSTNAME}' ==="
echo ""

# Generate the SSH host key
ssh-keygen -t ed25519 -f "$KEY_PATH" -N "" -C "${HOSTNAME} host key" -q
echo "SSH key pair generated."

# Convert to age public key
if command -v ssh-to-age &>/dev/null; then
  AGE_KEY=$(ssh-to-age < "${KEY_PATH}.pub")
elif command -v nix &>/dev/null; then
  AGE_KEY=$(nix shell nixpkgs#ssh-to-age --command ssh-to-age < "${KEY_PATH}.pub")
else
  echo "Error: Neither ssh-to-age nor nix found. Install one of them."
  rm -rf "$KEY_DIR"
  exit 1
fi

echo ""
echo "================================================"
echo "  Age public key:   ${AGE_KEY}"
echo "  SSH private key:  ${KEY_PATH}"
echo "  SSH public key:   ${KEY_PATH}.pub"
echo "================================================"
echo ""
echo "ACTION REQUIRED: Update ${SOPS_YAML}"
echo ""
echo "  1. Under 'keys:', add or replace the entry for ${HOSTNAME}:"
echo "       - &${HOSTNAME} ${AGE_KEY}"
echo ""
echo "  2. Under 'creation_rules:', ensure a rule exists:"
echo "       - path_regex: systems/secrets/${HOSTNAME}/[^/]+\.(yaml|json|env|ini)\$"
echo "         key_groups:"
echo "           - age:"
echo "               - *framework13h"
echo "               - *${HOSTNAME}"
echo ""
read -rp "Press Enter when ${SOPS_YAML} is updated (or Ctrl+C to abort)... "

# Verify the age key appears in .sops.yaml
if ! grep -q "$AGE_KEY" "$SOPS_YAML"; then
  echo ""
  echo "Warning: The age key was not found in ${SOPS_YAML}."
  read -rp "Continue anyway? (y/N) " confirm
  if [[ "$confirm" != [yY] ]]; then
    echo "Aborted. Key is still at: ${KEY_PATH}"
    exit 1
  fi
fi

# Run sops updatekeys
echo ""
echo "Running: sops updatekeys ${SECRETS_FILE}"
if sops updatekeys -y "$SECRETS_FILE"; then
  echo "Secrets re-encrypted successfully."
else
  echo "Error: sops updatekeys failed."
  echo "Key is still at: ${KEY_PATH}"
  exit 1
fi

echo ""
echo "=== Done ==="
echo ""
echo "SSH private key: ${KEY_PATH}"
echo ""
echo "WARNING: The key is in a temp dir and will be lost on reboot!"
echo "         Use it now (inject into image, copy somewhere safe, etc.)"
echo ""
echo "Next steps:"
echo "  1. Build the image:    nix build .#images.${HOSTNAME}-sdImage"
echo "  2. Inject the key:     sudo ./scripts/inject-host-key.sh ./result/sd-image/*.img.zst ${KEY_PATH}"
echo "  3. Flash to SD card:   sudo dd if=./result/sd-image/*.img of=/dev/sdX bs=4M status=progress"

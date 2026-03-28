#!/usr/bin/env bash
# Injects an SSH host key into a NixOS disk image so sops-nix can decrypt
# secrets on first boot. Works with SD images, raw disk images, etc.
#
# Usage:
#   sudo ./scripts/inject-host-key.sh <disk-image> <ssh-host-private-key> [partition]
#
# Arguments:
#   disk-image              Path to a raw disk image (.img or .img.zst — auto-decompresses)
#   ssh-host-private-key    Path to the SSH ed25519 private key to inject
#   partition               (Optional) Partition number for root, e.g. "2" for p2.
#                           Auto-detected if omitted.
#
# Examples:
#   # Directly from nix build output (auto-decompresses .zst)
#   sudo ./scripts/inject-host-key.sh ./result/sd-image/*.img.zst /tmp/tmp.XXXXX/ssh_host_ed25519_key
#
#   # Already decompressed
#   sudo ./scripts/inject-host-key.sh ./rpi-3a-plus.img /tmp/key
#
#   # Explicit partition
#   sudo ./scripts/inject-host-key.sh ./server.img /tmp/key 3
#
# After injection, flash with:
#   sudo dd if=./image.img of=/dev/sdX bs=4M status=progress

set -euo pipefail

IMG="${1:?Usage: $0 <disk-image.img> <ssh-host-private-key> [partition]}"
KEY="${2:?Usage: $0 <disk-image.img> <ssh-host-private-key> [partition]}"
PART_NUM="${3:-}"

if [[ ! -f "$IMG" ]]; then
  echo "Error: Image file '$IMG' not found"
  exit 1
fi

# Auto-decompress .zst files
if [[ "$IMG" == *.zst ]]; then
  DECOMPRESSED="./$(basename "${IMG%.zst}")"
  if [[ -f "$DECOMPRESSED" ]]; then
    echo "Decompressed image already exists: $DECOMPRESSED"
  else
    echo "Decompressing $IMG..."
    zstd -d "$IMG" -o "$DECOMPRESSED"
  fi
  IMG="$DECOMPRESSED"
fi

if [[ ! -f "$KEY" ]]; then
  echo "Error: SSH key file '$KEY' not found"
  exit 1
fi

if [[ $EUID -ne 0 ]]; then
  echo "Error: This script must be run as root (sudo)"
  exit 1
fi

MOUNT_DIR=$(mktemp -d)
LOOP=""

cleanup() {
  echo "Cleaning up..."
  umount "$MOUNT_DIR" 2>/dev/null || true
  [[ -n "$LOOP" ]] && losetup -d "$LOOP" 2>/dev/null || true
  rmdir "$MOUNT_DIR" 2>/dev/null || true
}
trap cleanup EXIT

echo "Setting up loop device for $IMG..."
LOOP=$(losetup --find --show --partscan "$IMG")
echo "Loop device: $LOOP"

# Determine root partition
if [[ -n "$PART_NUM" ]]; then
  ROOT_PART="${LOOP}p${PART_NUM}"
else
  # Auto-detect: try p2 first (common for SD images: p1=boot, p2=root),
  # fall back to p1 if only one partition exists
  if [[ -b "${LOOP}p2" ]]; then
    ROOT_PART="${LOOP}p2"
    echo "Auto-detected root partition: p2"
  elif [[ -b "${LOOP}p1" ]]; then
    ROOT_PART="${LOOP}p1"
    echo "Auto-detected root partition: p1"
  else
    echo "Error: No partitions found on $LOOP"
    lsblk "$LOOP"
    exit 1
  fi
fi

if [[ ! -b "$ROOT_PART" ]]; then
  echo "Error: Partition $ROOT_PART not found. Available partitions:"
  lsblk "$LOOP"
  exit 1
fi

echo "Mounting root partition ($ROOT_PART)..."
mount "$ROOT_PART" "$MOUNT_DIR"

# Create /etc/ssh if it doesn't exist
mkdir -p "$MOUNT_DIR/etc/ssh"

# Copy the SSH host key
echo "Injecting SSH host key..."
cp "$KEY" "$MOUNT_DIR/etc/ssh/ssh_host_ed25519_key"
chmod 600 "$MOUNT_DIR/etc/ssh/ssh_host_ed25519_key"

# Also inject the public key
if command -v ssh-keygen &>/dev/null; then
  ssh-keygen -y -f "$KEY" > "$MOUNT_DIR/etc/ssh/ssh_host_ed25519_key.pub"
  chmod 644 "$MOUNT_DIR/etc/ssh/ssh_host_ed25519_key.pub"
  echo "Public key also injected."
fi

echo "Unmounting..."
umount "$MOUNT_DIR"
losetup -d "$LOOP"
LOOP=""

echo ""
echo "Done! SSH host key injected into $IMG"
echo "Flash with:  sudo dd if=$IMG of=/dev/sdX bs=4M status=progress"

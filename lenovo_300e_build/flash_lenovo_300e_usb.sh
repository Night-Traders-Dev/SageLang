#!/usr/bin/env bash
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$HERE"

IMG="${1:-sageos.img}"
DEV="${2:-/dev/sdb}"

echo "=== SageOS Lenovo 300e USB Flasher ==="
echo "Image:  $IMG"
echo "Device: $DEV"
echo

if [ ! -f "$IMG" ]; then
    echo "ERROR: Image not found: $IMG"
    echo "Run ./build_lenovo_300e.sh first, or pass an image path."
    exit 1
fi

if [ ! -b "$DEV" ]; then
    echo "ERROR: Block device not found: $DEV"
    exit 1
fi

case "$DEV" in
    /dev/sda|/dev/nvme0n1|/dev/mmcblk0)
        echo "ERROR: Refusing to flash likely system disk: $DEV"
        exit 1
        ;;
esac

echo "Current device layout:"
lsblk "$DEV"
echo

echo "Unmounting mounted partitions on $DEV..."
while read -r part mountpoint; do
    if [ -n "${mountpoint:-}" ]; then
        sudo umount "/dev/$part" 2>/dev/null || true
    fi
done < <(lsblk -ln -o NAME,MOUNTPOINT "$DEV" | tail -n +2)

echo
echo "This will DESTROY all data on $DEV."
echo "Type exactly YES to continue:"
read -r confirm

if [ "$confirm" != "YES" ]; then
    echo "Aborted."
    exit 1
fi

echo
echo "Flashing image..."
sudo dd if="$IMG" of="$DEV" bs=4M status=progress conv=fsync

echo
echo "Syncing..."
sync

echo
echo "Re-reading partition table..."
sudo partprobe "$DEV" 2>/dev/null || true
sleep 1

echo
echo "Final device layout:"
lsblk "$DEV"

echo
echo "Done. SageOS Lenovo 300e image flashed to $DEV."
